import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var store = RecordingStore()
    @State private var isPickerPresented = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                if store.recordings.isEmpty {
                    ContentUnavailableView(
                        "No recordings yet",
                        systemImage: "waveform",
                        description: Text("Tap + to pick an audio file from Files, e.g. from Just Press Record's iCloud folder.")
                    )
                }
                ForEach(store.recordings) { recording in
                    NavigationLink(value: recording.id) {
                        RecordingRow(recording: recording)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        store.delete(id: store.recordings[index].id)
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                RecordingDetailView(store: store, id: id)
            }
            .navigationTitle("GHTranscribe")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPickerPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isPickerPresented,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                store.addAndProcess(fileURL: url)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

private struct RecordingRow: View {
    let recording: Recording

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(recording.sourceFilename)
                    .font(.headline)
                Text(recording.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusView
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch recording.status {
        case .pending, .transcribing, .summarizing:
            ProgressView()
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }
}

#Preview {
    ContentView()
}
