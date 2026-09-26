import CheetCore
import SwiftUI

/// Saved workspaces: rename, reorder, assign hotkeys, recall, delete.
struct WorkspacesPane: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("A workspace remembers a set of cheet windows and where they were. Save one from the menu bar › Workspaces, or press ⌥⌘S in a cheet.")
                .font(.callout).foregroundStyle(.secondary)
                .padding(16)
            if model.workspaces.isEmpty {
                ContentUnavailableView("No Workspaces Yet", systemImage: "square.stack.3d.up",
                                       description: Text("Open the cheets you want, arrange them, then save them as a workspace."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach($model.workspaces) { $workspace in
                        WorkspaceRow(model: model, workspace: $workspace)
                    }
                    .onMove { model.workspaces.move(fromOffsets: $0, toOffset: $1) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct WorkspaceRow: View {
    let model: AppModel
    @Binding var workspace: Workspace

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                TextField("Name", text: $workspace.name).textFieldStyle(.plain).font(.body.weight(.semibold))
                Text(workspace.windows.compactMap { model.cheet(id: $0.cheetID)?.title }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            HotkeyStatusBadge(model: model, action: .recallWorkspace(workspace.id), requested: workspace.hotkey)
            HotkeyRecorder(combo: $workspace.hotkey)
            Button("Recall") { AppController.shared.overlay.recall(workspaceID: workspace.id) }
            Button(role: .destructive) {
                model.workspaces.removeAll { $0.id == workspace.id }
            } label: {
                Image(systemName: "trash")
            }
            .help("Delete this workspace")
        }
        .padding(.vertical, 4)
    }
}
