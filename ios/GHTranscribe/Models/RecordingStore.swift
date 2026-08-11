import Foundation
import Observation

@Observable
final class RecordingStore {
    private(set) var recordings: [Recording] = []
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

    private func process(id: UUID, fileURL: URL) async {
        do {
            await update(id: id) { $0.status = .transcribing }
            let audioData = try await CloudFileLoader.loadData(from: fileURL)
            let transcript = try await OpenAIClient.shared.transcribe(
                audioData: audioData,
                filename: fileURL.lastPathComponent
            )
            await update(id: id) {
                $0.transcript = transcript
                $0.status = .summarizing
            }
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
