import Foundation
import Observation

@Observable
final class RecordingStore {
    private(set) var recordings: [Recording] = []
    private(set) var progress: [UUID: RecordingProgress] = [:]
    private let storageURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storageURL = docs.appendingPathComponent("recordings.json")
        load()
    }

    func addAndProcess(fileURL: URL) {
        let id = UUID()
        let recording = Recording(
            id: id,
            sourceFilename: fileURL.lastPathComponent,
            sourceBookmark: try? fileURL.bookmarkData(),
            createdAt: Date(),
            status: .pending
        )
        recordings.insert(recording, at: 0)
        save()

        Task {
            await process(id: id, fileURL: fileURL)
        }
    }

    func delete(id: UUID) {
        recordings.removeAll { $0.id == id }
        save()
    }

    func retry(id: UUID) {
        guard let recording = recordings.first(where: { $0.id == id }),
              let bookmark = recording.sourceBookmark
        else {
            Task {
                await update(id: id) {
                    $0.errorMessage = "Can't retry -- the original file reference was lost. Re-pick it instead."
                }
            }
            return
        }

        Task {
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
                await update(id: id) {
                    $0.status = .pending
                    $0.errorMessage = nil
                    $0.transcript = nil
                    $0.summaryHTML = nil
                    $0.transcriptFileNote = nil
                    $0.title = nil
                }
                await process(id: id, fileURL: url)
            } catch {
                await update(id: id) {
                    $0.status = .failed
                    $0.errorMessage = "Can't retry -- the original file reference was lost. Re-pick it instead."
                }
            }
        }
    }

    /// Re-attempts just the sidecar file write (e.g. after granting folder
    /// access in Settings), without re-running transcription/summarization.
    func retryTranscriptFileSave(id: UUID) {
        guard let recording = recordings.first(where: { $0.id == id }),
              let transcript = recording.transcript,
              let bookmark = recording.sourceBookmark
        else { return }

        Task {
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
                let note = Self.writeTranscriptSidecar(
                    title: recording.title ?? recording.sourceFilename,
                    transcript: transcript,
                    besideSourceURL: url
                )
                await update(id: id) { $0.transcriptFileNote = note }
            } catch {
                await update(id: id) {
                    $0.transcriptFileNote = "Couldn't save the transcription file next to the recording: \(error.localizedDescription)"
                }
            }
        }
    }

    private func process(id: UUID, fileURL: URL) async {
        let startedAt = Date()
        defer {
            Task { @MainActor in self.progress[id] = nil }
        }
        do {
            await update(id: id) { $0.status = .transcribing }
            await setStage(id: id, .downloading, startedAt: startedAt)
            let audioData = try await CloudFileLoader.loadData(from: fileURL)

            await setStage(id: id, .uploading(fraction: 0), startedAt: startedAt)
            let transcript = try await OpenAIClient.shared.transcribe(
                audioData: audioData,
                filename: fileURL.lastPathComponent
            ) { [weak self] fraction in
                guard let self else { return }
                let stage: RecordingProgress.Stage = fraction >= 0.999
                    ? .waitingForTranscription
                    : .uploading(fraction: fraction)
                Task { @MainActor in self.setStage(id: id, stage, startedAt: startedAt) }
            }
            await update(id: id) {
                $0.transcript = transcript
                $0.status = .summarizing
            }

            let title = await TitleResolver.resolveTitle(fileURL: fileURL, transcript: transcript)
            await update(id: id) {
                $0.title = title
                $0.transcriptFileNote = Self.writeTranscriptSidecar(
                    title: title,
                    transcript: transcript,
                    besideSourceURL: fileURL
                )
            }
            await setStage(id: id, .summarizing, startedAt: startedAt)
            let html = try await OpenAIClient.shared.summarize(transcript: transcript)
            await update(id: id) {
                $0.summaryHTML = html
                $0.status = .done
            }
        } catch {
            await update(id: id) {
                $0.status = .failed
                $0.errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func setStage(id: UUID, _ stage: RecordingProgress.Stage, startedAt: Date) {
        progress[id] = RecordingProgress(stage: stage, startedAt: startedAt)
    }

    /// Writes the transcript beside the original recording as
    /// "<name>-openai-transcription.txt", with the title as its first line.
    /// Returns nil on success, or a user-facing note if the sandbox wouldn't
    /// allow it (the transcript is still available in-app either way).
    private static func writeTranscriptSidecar(title: String, transcript: String, besideSourceURL fileURL: URL) -> String? {
        do {
            _ = try CloudFileLoader.writeSidecarFile(
                "\(title)\n\n\(transcript)",
                besideSourceURL: fileURL,
                suffix: "-openai-transcription.txt"
            )
            return nil
        } catch {
            return "Couldn't save the transcription file next to the recording: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func update(id: UUID, _ mutate: (inout Recording) -> Void) {
        guard let index = recordings.firstIndex(where: { $0.id == id }) else { return }
        mutate(&recordings[index])
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([Recording].self, from: data)
        else { return }
        recordings = decoded.sorted { $0.createdAt > $1.createdAt }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(recordings) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
