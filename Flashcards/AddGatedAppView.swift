import SwiftUI

/// Pick an app to gate — from the ones whose links we know, or by typing your own.
struct AddGatedAppView: View {
    let onAdd: (GatedApp) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var customName = ""
    @State private var customScheme = ""

    private var existing: Set<String> { Set(GatedApps.all.map(\.id)) }

    var body: some View {
        NavigationStack {
            List {
                Section("Known apps") {
                    ForEach(GatedApps.catalogue.filter { !existing.contains($0.id) }) { app in
                        Button {
                            onAdd(app)
                            dismiss()
                        } label: {
                            LabeledContent(app.name, value: app.scheme)
                        }
                    }
                }
                Section {
                    TextField("App name", text: $customName)
                    TextField("Link, e.g. spotify://", text: $customScheme)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Add") {
                        onAdd(GatedApp(id: slug, name: customName.trimmed, scheme: customScheme.trimmed))
                        dismiss()
                    }
                    .disabled(slug.isEmpty || customScheme.trimmed.isEmpty || existing.contains(slug))
                    if existing.contains(slug) {
                        Text("\(customName.trimmed) is already on the list.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Something else")
                } footer: {
                    Text("The link is the app's URL scheme. Search \"<app name> URL scheme\" if you don't know it — most are the app's name followed by ://")
                }
            }
            .navigationTitle("Add an app")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var slug: String {
        customName.trimmed.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespaces) }
}
