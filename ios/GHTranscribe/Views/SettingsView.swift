import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = KeychainStore.loadAPIKey() ?? ""

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
        }
    }
}

#Preview {
    SettingsView()
}
