import SwiftUI
import PectoKit

struct APIKeysSettingsView: View {
    let model: AppModel

    var body: some View {
        Form {
            ForEach(ProviderCatalog.all) { info in
                if info.requiresAPIKey {
                    ProviderKeyRow(model: model, info: info)
                } else {
                    appleSection(info)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("API Keys")
    }

    private func appleSection(_ info: ProviderInfo) -> some View {
        Section {
            HStack(spacing: 8) {
                StatusDot(on: model.appleAvailability.isAvailable)
                if let explanation = model.appleAvailability.explanation {
                    Text(explanation)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Ready — runs entirely on this Mac, no API key needed.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
        } header: {
            Text(info.displayName)
        }
    }
}

private struct StatusDot: View {
    let on: Bool

    var body: some View {
        Circle()
            .fill(on ? Color.green : Color.secondary.opacity(0.4))
            .frame(width: 8, height: 8)
    }
}

/// One provider's key management: masked entry, save/remove, and a Test
/// button that fires a cheap API call with the draft or the stored key.
private struct ProviderKeyRow: View {
    let model: AppModel
    let info: ProviderInfo
    @State private var draft = ""
    @State private var testState: TestState = .idle

    private enum TestState: Equatable {
        case idle, testing, success
        case failure(String)
    }

    private var hasStoredKey: Bool {
        model.storedKeyProviders.contains(info.id)
    }

    var body: some View {
        Section {
            SecureField(info.keyPlaceholder, text: $draft)
                .onSubmit(saveKey)
                .onChange(of: draft) { testState = .idle }
            HStack {
                Button("Save Key", action: saveKey)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Test", action: testKey)
                    .disabled(testState == .testing
                        || (!hasStoredKey && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                if hasStoredKey {
                    Button("Remove Key", role: .destructive, action: removeKey)
                }
                Spacer()
                testFeedback
            }
            .font(.callout)
        } header: {
            HStack(spacing: 8) {
                StatusDot(on: hasStoredKey)
                Text(info.displayName)
                if !hasStoredKey {
                    Text("— no key yet")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var testFeedback: some View {
        switch testState {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView()
                .controlSize(.small)
        case .success:
            Label("Key works", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    private func saveKey() {
        KeychainService.saveAPIKey(draft, for: info.id)
        draft = ""
        testState = .idle
        model.refreshAPIKeyStatus()
    }

    private func removeKey() {
        KeychainService.deleteAPIKey(for: info.id)
        draft = ""
        testState = .idle
        model.refreshAPIKeyStatus()
    }

    /// Tests the draft if one is typed, else the stored key. The keychain
    /// read stays off the main actor — it can block on a permission prompt.
    private func testKey() {
        guard let client = model.providers.client(for: info.id) else { return }
        let provider = info.id
        let draftKey = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        testState = .testing
        Task {
            let key: String? = draftKey.isEmpty
                ? await Task.detached(operation: { KeychainService.loadAPIKey(for: provider) }).value
                : draftKey
            guard let key else {
                testState = .failure("No key to test yet.")
                return
            }
            do {
                try await client.validateKey(key)
                testState = .success
            } catch {
                let message = (error as? RunError)?.message ?? error.localizedDescription
                testState = .failure(message)
            }
        }
    }
}
