import SwiftUI

/// Routes pushable onto the detail column's stack.
enum DetailRoute: Hashable {
    case config
}

struct MainWindowView: View {
    @Bindable var model: AppModel
    @State private var detailPath: [DetailRoute] = []

    var body: some View {
        NavigationSplitView {
            TaskListView(model: model)
        } detail: {
            NavigationStack(path: $detailPath) {
                TaskEditorView(model: model, detailPath: $detailPath)
                    .navigationDestination(for: DetailRoute.self) { route in
                        switch route {
                        case .config:
                            TaskConfigView(model: model)
                        }
                    }
            }
        }
        // Switching (or losing) the selected task pops the config view.
        .onChange(of: model.selectedPath) {
            detailPath.removeAll()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            statusArea
        }
        .alert(
            "That didn't work",
            isPresented: Binding(
                get: { model.operationError != nil },
                set: { if !$0 { model.operationError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.operationError ?? "")
        }
    }

    /// Run feedback lives in the window too — notifications can be
    /// unavailable for unsigned dev builds, and the app must never look dead.
    /// Success is the quiet path (notch flash only); the bar shows problems.
    @ViewBuilder
    private var statusArea: some View {
        VStack(spacing: 0) {
            if let outcome = model.runner.lastOutcome, outcome.kind != .success {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: icon(for: outcome.kind))
                        .foregroundStyle(color(for: outcome.kind))
                    Text(outcome.message)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        model.runner.clearOutcome()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
            }

            if !model.hasAPIKey {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .foregroundStyle(.yellow)
                    Text("Add your Anthropic API key to run tasks.")
                    Spacer()
                    SettingsLink {
                        Text("Open Settings…")
                    }
                }
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
    }

    private func icon(for kind: RunOutcome.Kind) -> String {
        switch kind {
        case .success: "checkmark.circle.fill"
        case .failure: "xmark.circle.fill"
        case .refusal: "exclamationmark.triangle.fill"
        }
    }

    private func color(for kind: RunOutcome.Kind) -> Color {
        switch kind {
        case .success: .green
        case .failure: .red
        case .refusal: .yellow
        }
    }
}
