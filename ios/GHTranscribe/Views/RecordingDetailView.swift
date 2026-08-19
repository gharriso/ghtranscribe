import SwiftUI

struct RecordingDetailView: View {
    let store: RecordingStore
    let id: UUID

    @State private var showTranscript = false
    @State private var isSharePresented = false
    @State private var shareAttributedString: NSAttributedString?

    private var recording: Recording? {
        store.recordings.first(where: { $0.id == id })
    }

    var body: some View {
        Group {
            if let recording {
                content(for: recording)
            } else {
                Text("Recording not found.")
            }
        }
    }

    @ViewBuilder
    private func content(for recording: Recording) -> some View {
        Group {
            switch recording.status {
            case .pending, .transcribing, .summarizing:
                Group {
                    if let progress = store.progress[recording.id] {
                        ProgressStageView(progress: progress)
                    } else {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text(statusLabel(for: recording))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed:
                ScrollView {
                    VStack(spacing: 16) {
                        Text(recording.errorMessage ?? "Something went wrong.")
                            .foregroundStyle(.red)
                        Button("Retry", systemImage: "arrow.clockwise") {
                            store.retry(id: recording.id)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                }
            case .done:
                VStack(spacing: 0) {
                    if let note = recording.transcriptFileNote {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Button("Retry saving file") {
                                store.retryTranscriptFileSave(id: recording.id)
                            }
                            .font(.caption)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HTMLView(html: titledSummaryHTML(for: recording))
                }
            }
        }
        .navigationTitle(recording.sourceFilename)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if recording.status == .done {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            share(recording)
                        } label: {
                            Label("Share Summary", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            showTranscript = true
                        } label: {
                            Label("Show Transcript", systemImage: "doc.text")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showTranscript) {
            NavigationStack {
                ScrollView {
                    Text(titledTranscript(for: recording))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .navigationTitle("Transcript")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $isSharePresented) {
            if let shareAttributedString {
                ShareSheet(items: [shareAttributedString])
            }
        }
    }

    private func share(_ recording: Recording) {
        shareAttributedString = HTMLRenderer.attributedString(fromHTML: titledSummaryHTML(for: recording))
        isSharePresented = true
    }

    private func titledSummaryHTML(for recording: Recording) -> String {
        let title = recording.title ?? recording.sourceFilename
        return "<h1>\(title)</h1>" + (recording.summaryHTML ?? "")
    }

    private func titledTranscript(for recording: Recording) -> String {
        let title = recording.title ?? recording.sourceFilename
        return "\(title)\n\n\(recording.transcript ?? "")"
    }

    private func statusLabel(for recording: Recording) -> String {
        switch recording.status {
        case .pending: return "Waiting to start..."
        case .transcribing: return "Transcribing..."
        case .summarizing: return "Summarizing..."
        case .done, .failed: return ""
        }
    }
}
