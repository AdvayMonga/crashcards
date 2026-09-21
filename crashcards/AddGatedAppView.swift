import SwiftUI

/// Pick an app to gate — from the ones whose links we know, or by typing your own.
struct AddGatedAppView: View {
    let onClose: () -> Void
    let onAdd: (GatedApp) -> Void

    @State private var customName = ""
    @State private var customScheme = ""

    private var existing: Set<String> { Set(GatedApps.all.map(\.id)) }
    private var canAdd: Bool {
        !slug.isEmpty && !customScheme.trimmed.isEmpty && !existing.contains(slug)
    }

    var body: some View {
        CrashModal(title: "Add an app", onCancel: onClose) {
            VStack(spacing: 16) {
                knownPanel
                customPanel
            }
        }
    }

    private var knownPanel: some View {
        Panel(title: "Known apps") {
            let known = GatedApps.catalogue.filter { !existing.contains($0.id) }
            ForEach(Array(known.enumerated()), id: \.element.id) { index, app in
                PanelRow(first: index == 0) {
                    Button {
                        Haptics.tap()
                        onAdd(app)
                        onClose()
                    } label: {
                        HStack {
                            Text(app.name)
                                .font(.brandLabel)
                                .foregroundStyle(Brand.ink)
                            Spacer(minLength: 12)
                            Text(app.scheme)
                                .font(.reading(13))
                                .foregroundStyle(Brand.inkFaint)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
    }

    private var customPanel: some View {
        Panel(title: "Something else",
              footnote: "The link is the app's URL scheme. Search \"<app name> URL scheme\" if you don't know it — most are the app's name followed by ://") {
            PanelRow(first: true) {
                CrashField(placeholder: "App name", text: $customName)
            }
            PanelRow {
                CrashField(placeholder: "Link, e.g. spotify://", text: $customScheme)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            PanelRow {
                VStack(spacing: 8) {
                    Button("Add") {
                        Haptics.knock()
                        onAdd(GatedApp(id: slug, name: customName.trimmed,
                                       scheme: customScheme.trimmed))
                        onClose()
                    }
                    .buttonStyle(.solid)
                    .disabled(!canAdd)
                    .opacity(canAdd ? 1 : 0.45)

                    if existing.contains(slug) {
                        Text("\(customName.trimmed) is already on the list.")
                            .font(.brandCaption)
                            .foregroundStyle(Brand.inkFaint)
                    }
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
