import SwiftUI

struct MainWindowView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            TaskListView(model: model)
        } detail: {
            TaskEditorView(model: model)
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
}
