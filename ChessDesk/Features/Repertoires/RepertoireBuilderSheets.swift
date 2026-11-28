import ChessCore
import SwiftUI
import UIKit

// The sheets of the builder: the whole tree, the note of a move, the PGN import.

/// The whole repertoire, full height: every run of moves on its own row, the
/// alternatives indented under the move they leave from. Tap a move to stand
/// on it on the board.
struct RepertoireTreeSheet: View {
    let model: RepertoireBuilderModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let rows = RepertoireTree.outline(model.tree)
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: CD.Space.s2) {
                    Text("Move tree")
                        .cdFont(.plateTitle)
                        .foregroundStyle(CD.ink)
                        .accessibilityAddTraits(.isHeader)
                    if let detail = model.detail {
                        Text("\(CDFormat.plural(detail.moves, "move")), \(CDFormat.plural(detail.lines, "line"))")
                            .cdFont(.meta)
                            .foregroundStyle(CD.ink3)
                            .cdNumber()
                    }
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.cd(.ghost))
            }
            .padding(.horizontal, CD.Space.s20)
            .padding(.top, CD.Space.s24)
            .padding(.bottom, CD.Space.s8)
            CDHairline()
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let note = model.detail?.rootComment, !note.isEmpty {
                            Text(note)
                                .cdFont(.ledeSmall)
                                .foregroundStyle(CD.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, CD.Space.s8)
                                .padding(.bottom, CD.Space.s8)
                        }
                        ForEach(rows) { row in
                            TreeRow(row: row, current: model.path) { path in
                                model.goTo(path)
                                dismiss()
                            }
                            .id(row.id)
                        }
                    }
                    .padding(.horizontal, CD.Space.s12)
                    .padding(.vertical, CD.Space.s12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onAppear {
                    // Open on the row that holds the current move.
                    if let row = rows.first(where: { $0.moves.contains { $0.path == model.path } }) {
                        reader.scrollTo(row.id, anchor: .center)
                    }
                }
            }
        }
        .background(CD.canvas.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private struct TreeRow: View {
    let row: RepertoireTree.OutlineRow
    let current: [String]
    let select: ([String]) -> Void

    var body: some View {
        let depth = CGFloat(min(row.depth, 6))
        RepertoireFlowLayout(spacing: 0) {
            ForEach(row.moves) { move in
                let isCurrent = move.path == current
                let onPath = current.starts(with: move.path)
                Button {
                    select(move.path)
                } label: {
                    HStack(spacing: 3) {
                        if let number = RepertoireTree.number(ply: move.ply, opensRow: move.opensRow) {
                            Text(number).cdFont(.meta).foregroundStyle(CD.ink4).cdNumber()
                        }
                        Text(move.san + move.glyph)
                            .cdFont(.san)
                            .foregroundStyle(isCurrent ? CD.ink : onPath ? CD.ink : CD.ink2)
                        if move.hasNote {
                            Image(systemName: "text.bubble")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(CD.ink4)
                        }
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 30)
                    .background(
                        isCurrent ? CD.accentSoft : .clear,
                        in: RoundedRectangle(cornerRadius: CD.Radius.sm, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: CD.Radius.sm, style: .continuous)
                            .strokeBorder(isCurrent ? CD.accentLine : .clear, lineWidth: 1)
                    )
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(CDPressStyle())
                .accessibilityLabel("\(RepertoireTree.number(ply: move.ply, opensRow: true) ?? "") \(move.san)")
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
            }
        }
        .padding(.leading, depth * 14)
        .overlay(alignment: .leading) {
            // An alternative hangs from a rule, so its depth reads at a glance.
            if row.depth > 0 {
                Rectangle().fill(CD.lineStrong).frame(width: 1).padding(.leading, depth * 14 - 6).padding(.vertical, 6)
            }
        }
    }
}

/// Lays its children out in rows, wrapping like words.
struct RepertoireFlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        return CGSize(width: width.isFinite ? width : rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arranged = arrange(subviews, width: bounds.width)
        for (index, origin) in arranged.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified
            )
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (origins: [CGPoint], width: CGFloat, height: CGFloat) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (origins, widest, y + rowHeight)
    }
}

/// The note and the glyph of the current move; at the start, the note
/// before the first move.
struct RepertoireNoteSheet: View {
    let model: RepertoireBuilderModel

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var nag: Int?
    @State private var isSaving = false
    @FocusState private var focused: Bool

    private var node: RepertoireNode? { model.currentNode }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s20) {
                VStack(alignment: .leading, spacing: CD.Space.s4) {
                    Text(node.map { "Note on \(RepertoireTree.number(ply: $0.ply, opensRow: true) ?? "") \($0.san)" } ?? "Note before the first move")
                        .cdFont(.plateTitle)
                        .foregroundStyle(CD.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(node == nil ? "Shown when the repertoire opens." : "Why this move: the plan, the trap, the idea. It is shown when you learn the line.")
                        .cdFont(.small)
                        .foregroundStyle(CD.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                TextEditor(text: $text)
                    .focused($focused)
                    .font(CDFont.lede.font)
                    .foregroundStyle(CD.ink)
                    .scrollContentBackground(.hidden)
                    .padding(CD.Space.s8)
                    .frame(minHeight: 140)
                    .background(CD.surface3, in: RoundedRectangle(cornerRadius: CD.Radius.md, style: .continuous))
                    .hairline(CD.lineStrong, radius: CD.Radius.md)
                    .accessibilityLabel("Note")
                if node != nil {
                    VStack(alignment: .leading, spacing: CD.Space.s8) {
                        Text("Mark the move")
                            .cdFont(.small)
                            .foregroundStyle(CD.ink2)
                        HStack(spacing: CD.Space.s8) {
                            ForEach(RepertoireTree.glyphs, id: \.nag) { glyph in
                                let isOn = nag == glyph.nag
                                Button {
                                    nag = isOn ? nil : glyph.nag
                                } label: {
                                    Text(glyph.text)
                                        .font(.custom("Newsreader16pt-SemiBold", size: 18, relativeTo: .body))
                                        .foregroundStyle(isOn ? CD.accentStrong : CD.ink2)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .background(
                                            isOn ? CD.accentSoft : CD.surface2,
                                            in: RoundedRectangle(cornerRadius: CD.Radius.md, style: .continuous)
                                        )
                                        .hairline(isOn ? CD.accentLine : CD.lineStrong, radius: CD.Radius.md)
                                }
                                .buttonStyle(CDPressStyle())
                                .accessibilityLabel(Self.spoken(glyph.nag))
                                .accessibilityAddTraits(isOn ? .isSelected : [])
                            }
                        }
                    }
                }
                VStack(spacing: CD.Space.s8) {
                    Button {
                        save()
                    } label: {
                        if isSaving { ProgressView().tint(CD.accentInk) } else { Text("Save") }
                    }
                    .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
                    .disabled(isSaving)
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.cd(.ghost, fullWidth: true))
                }
            }
            .padding(.horizontal, CD.Space.s24)
            .padding(.top, CD.Space.s32)
            .padding(.bottom, CD.Space.s24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(CD.canvas.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .onAppear {
            text = node?.comments.joined(separator: "\n\n") ?? model.detail?.rootComment ?? ""
            nag = node?.nags.first
        }
    }

    private func save() {
        isSaving = true
        Task {
            await model.annotate(comment: text, glyph: nag.map(GlyphChange.set) ?? .clear)
            isSaving = false
            dismiss()
        }
    }

    private static func spoken(_ nag: Int) -> String {
        switch nag {
        case 1: "Good move"
        case 2: "Mistake"
        case 3: "Brilliant move"
        case 4: "Blunder"
        case 5: "Interesting move"
        default: "Dubious move"
        }
    }
}

/// Replaces the tree with the games of a PGN.
struct RepertoireImportSheet: View {
    let model: RepertoireBuilderModel

    @Environment(\.dismiss) private var dismiss
    @State private var pgn = ""
    @State private var isWorking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s20) {
                VStack(alignment: .leading, spacing: CD.Space.s4) {
                    Text("Import a PGN")
                        .cdFont(.plateTitle)
                        .foregroundStyle(CD.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("Every game of the PGN is merged into one tree, variations included. It replaces the moves of this repertoire.")
                        .cdFont(.small)
                        .foregroundStyle(CD.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                TextEditor(text: $pgn)
                    .font(CDFont.mono.font)
                    .foregroundStyle(CD.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .scrollContentBackground(.hidden)
                    .padding(CD.Space.s8)
                    .frame(minHeight: 180)
                    .background(CD.surface3, in: RoundedRectangle(cornerRadius: CD.Radius.md, style: .continuous))
                    .hairline(CD.lineStrong, radius: CD.Radius.md)
                    .overlay(alignment: .topLeading) {
                        if pgn.isEmpty {
                            Text("1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 …")
                                .font(CDFont.mono.font)
                                .foregroundStyle(CD.ink4)
                                .padding(CD.Space.s16)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel("PGN")
                if let notice = model.notice, notice.isError {
                    Text(notice.text)
                        .cdFont(.small)
                        .foregroundStyle(CD.loss)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: CD.Space.s8) {
                    Button {
                        replace()
                    } label: {
                        if isWorking { ProgressView().tint(CD.accentInk) } else { Text("Replace the tree") }
                    }
                    .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
                    .disabled(isWorking || pgn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Paste from the clipboard") {
                        if let text = UIPasteboard.general.string { pgn = text }
                    }
                    .buttonStyle(.cd(.secondary, size: .large, fullWidth: true))
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.cd(.ghost, fullWidth: true))
                }
            }
            .padding(.horizontal, CD.Space.s24)
            .padding(.top, CD.Space.s32)
            .padding(.bottom, CD.Space.s24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(CD.canvas.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        #if DEBUG
            .onAppear { if let sample = RepertoireDebug.samplePGN { pgn = sample } }
        #endif
    }

    private func replace() {
        isWorking = true
        Task {
            let done = await model.importPGN(pgn)
            isWorking = false
            if done { dismiss() }
        }
    }
}
