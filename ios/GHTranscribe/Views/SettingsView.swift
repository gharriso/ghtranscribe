import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = KeychainStore.loadAPIKey() ?? ""
    @State private var grantedFolderName: String? = FolderAccessStore.grantedFolderName
    @State private var isFolderPickerPresented = false

    var body: some View {
        NavigationStack {
            Form {
                Section("OpenAI API Key") {
                    SecureField("sk-...", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Text("Stored in the Keychain on this device and sent directly to OpenAI's API -- no other server is involved.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Recordings Folder") {
                    if let folderName = grantedFolderName {
                        HStack {
                            Text(folderName)
                            Spacer()
                            Button("Change") { isFolderPickerPresented = true }
                        }
                        Button("Remove Access", role: .destructive) {
                            FolderAccessStore.clear()
                            grantedFolderName = nil
                        }
                    } else {
                        Button("Choose Folder...") { isFolderPickerPresented = true }
                    }
                }
                Section {
                    Text("Picking a single audio file only grants access to that file, not its folder. Granting access to the containing folder (e.g. Just Press Record's iCloud folder) lets the app save the \"-openai-transcription.txt\" file alongside each recording. Without it, the transcript still stays in-app either way.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        if apiKey.isEmpty {
                            KeychainStore.clear()
                        } else {
                            KeychainStore.save(apiKey: apiKey)
                        }
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $isFolderPickerPresented,
                allowedContentTypes: [.folder]
            ) { result in
                if case .success(let url) = result {
                    try? FolderAccessStore.save(folderURL: url)
                    grantedFolderName = url.lastPathComponent
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
