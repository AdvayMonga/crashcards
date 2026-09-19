import SwiftUI

/// Lists everything that went wrong in the last folder scan: unreadable folders, and
/// per-file format problems with the line number and the format that was expected.
///
/// Read-only. The app never edits your `.md` files — this screen tells you what to change
/// so you can fix it in Obsidian yourself.
struct FileProblemsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(FlagStore.self) private var flags

    var body: some View {
        List {
            if library.issueCount == 0 && flags.loadError == nil {
                Section {
                    Label("No problems found", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            }

            if let error = flags.loadError {
                Section("\(FlagStore.filename)") {
                    Text(error).font(.callout)
                    Text("Flagging is paused so this file isn't overwritten. Fix or delete it, then reopen the app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !library.folderErrors.isEmpty {
                Section("Folders") {
                    ForEach(library.folderErrors, id: \.self) { error in
                        Label(error, systemImage: "folder.badge.questionmark")
                            .font(.callout)
                    }
                }
            }

            ForEach(library.fileIssues) { file in
                Section(file.filename) {
                    ForEach(file.issues) { issue in
                        issueRow(issue)
                    }
                }
            }

            Section("Correct format") {
                codeBlock(MarkdownParser.formatGuide)
                Text("Everything else — prose, YAML frontmatter, code blocks — is ignored.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("File Problems")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func issueRow(_ issue: ParseIssue) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(issue.line > 0 ? "Line \(issue.line)" : "Whole file")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(issue.message)
                .font(.callout)
            if !issue.excerpt.isEmpty {
                codeBlock(issue.excerpt)
            }
            Text("Expected:")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            codeBlock(issue.expected)
        }
        .padding(.vertical, 4)
    }

    private func codeBlock(_ text: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
