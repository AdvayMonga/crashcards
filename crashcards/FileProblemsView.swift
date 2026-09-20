import SwiftUI

/// Lists everything that went wrong in the last folder scan: unreadable folders, and
/// per-file format problems with the line number and the format that was expected.
///
/// Read-only. The app never edits your `.md` files — this screen tells you what to change
/// so you can fix it in Obsidian yourself.
struct FileProblemsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(FlagStore.self) private var flags
    let onClose: () -> Void

    var body: some View {
        ZStack {
            TableBackground()

            ScrollView {
                VStack(spacing: 16) {
                    if library.issueCount == 0 && flags.loadError == nil {
                        Panel {
                            PanelRow(first: true) {
                                HStack(spacing: 12) {
                                    PixelIcon(glyph: .check, size: 18, color: Brand.green)
                                    Text("No problems found")
                                        .font(.brandLabel)
                                        .foregroundStyle(Brand.ink)
                                }
                            }
                        }
                    }

                    if let error = flags.loadError {
                        Panel(title: FlagStore.filename,
                              footnote: "Flagging is paused so this file isn't overwritten. Fix or delete it, then reopen the app.") {
                            PanelRow(first: true) {
                                Text(error)
                                    .font(.reading(14))
                                    .foregroundStyle(Brand.mult)
                            }
                        }
                    }

                    if !library.folderErrors.isEmpty {
                        Panel(title: "Folders") {
                            ForEach(Array(library.folderErrors.enumerated()), id: \.element) { index, error in
                                PanelRow(first: index == 0) {
                                    HStack(alignment: .top, spacing: 12) {
                                        PixelIcon(glyph: .folder, size: 16, color: Brand.orange)
                                        Text(error)
                                            .font(.reading(14))
                                            .foregroundStyle(Brand.ink)
                                    }
                                }
                            }
                        }
                    }

                    ForEach(library.fileIssues) { file in
                        Panel(title: file.filename) {
                            ForEach(Array(file.issues.enumerated()), id: \.element.id) { index, issue in
                                PanelRow(first: index == 0) { issueRow(issue) }
                            }
                        }
                    }

                    Panel(title: "Correct format",
                          footnote: "Everything else — prose, YAML frontmatter, code blocks — is ignored.") {
                        PanelRow(first: true) {
                            codeBlock(MarkdownParser.formatGuide)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .top) { header }
    }

    private var header: some View {
        HStack(spacing: 12) {
            HeaderChip(glyph: .close, name: "Close") { onClose() }
            Text("File problems")
                .font(.brandTitle)
                .foregroundStyle(Brand.ink)
                .shadow(color: Brand.outline, radius: 0, x: 2, y: 2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }

    private func issueRow(_ issue: ParseIssue) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(issue.line > 0 ? "Line \(issue.line)" : "Whole file")
                .font(.brandCaption)
                .foregroundStyle(Brand.gold)
            Text(issue.message)
                .font(.reading(14))
                .foregroundStyle(Brand.ink)
            if !issue.excerpt.isEmpty {
                codeBlock(issue.excerpt)
            }
            Text("Expected:")
                .font(.brandCaption)
                .foregroundStyle(Brand.inkFaint)
            codeBlock(issue.expected)
        }
    }

    private func codeBlock(_ text: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Brand.ink)
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Brand.surfaceLedge)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Brand.outline, lineWidth: 2))
        }
    }
}
