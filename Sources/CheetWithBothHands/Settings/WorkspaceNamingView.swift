import SwiftUI

/// "Save Workspace…": a name field that warns when saving will replace an existing workspace.
struct WorkspaceNamingView: View {
    let existingNames: [String]
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @State var name: String

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var replaces: Bool {
        existingNames.contains { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Workspace").font(.headline)
            Text("Saves the cheet windows that are open now, with their positions and sizes.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            if replaces {
                Label("A workspace with this name exists. Saving replaces its windows.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button(replaces ? "Replace" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
    }
}
