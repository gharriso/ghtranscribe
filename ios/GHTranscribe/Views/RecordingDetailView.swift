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
                VStack(spacing: 12) {
                    ProgressView()
                    Text(statusLabel(for: recording))
                        .foregroundStyle(.secondary)
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
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HTMLView(html: recording.summaryHTML ?? "")
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
                    Text(recording.transcript ?? "")
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
        let html = "<b>\(recording.sourceFilename)</b><br><br>" + (recording.summaryHTML ?? "")
        shareAttributedString = HTMLRenderer.attributedString(fromHTML: html)
        isSharePresented = true
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
