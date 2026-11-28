import ChessCore
import SwiftUI
import UIKit

/// The repertoire builder, laid out for one hand on a phone.
///
/// Top to bottom: the board; the current line as one row of moves; the moves
/// that can be played from the position (the repertoire's own first, then
/// what is commonly played, with their numbers); and a row of five actions
/// under the thumb. A move is added by tapping it in the list or by playing
/// it on the board. The whole tree opens as a sheet. A working screen: no
/// ornament.
struct RepertoireBuilderScreen: View {
    let id: String
    /// The name known before the repertoire is read.
    let name: String

    @Environment(AppModel.self) private var app
    @State private var model: RepertoireBuilderModel?

    var body: some View {
        Group {
            if let model {
                switch model.phase {
                case .loading:
                    LoadingView()
                case let .failed(message):
                    LoadFailureView(title: "This repertoire did not load", message: message) {
                        Task { await model.load() }
                    }
                case .ready:
                    RepertoireBuilder(model: model)
                }
            } else if app.playerToken == nil {
                LoadFailureView(title: "Sign in to open this repertoire", message: "Repertoires belong to an account.")
            } else {
                LoadingView()
            }
        }
        .navigationTitle(model?.detail?.name ?? name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .cdPage()
        .task {
            guard model == nil, let token = app.playerToken else { return }
            let fresh = RepertoireBuilderModel(
                id: id, api: app.api, token: token, onUnauthorized: { app.sessionExpired() }
            )
            #if DEBUG
                await RepertoireDebug.prepare(fresh)
            #else
                await fresh.load()
            #endif
            model = fresh
        }
    }
}

private struct RepertoireBuilder: View {
    @Bindable var model: RepertoireBuilderModel

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var sheet: BuilderSheet?
    @State private var training: RepertoireTrainingRequest?
    @State private var confirmsRemoval = false
    @State private var confirmsSeed = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var showsGames = false

    var body: some View {
        GeometryReader { proxy in
            let wide = sizeClass == .regular && proxy.size.width > proxy.size.height
            if wide {
                HStack(spacing: 0) {
                    board
                        .padding(CD.Space.s24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Rectangle().fill(CD.line).frame(width: 1)
                    panel.frame(width: min(460, proxy.size.width * 0.42))
                }
            } else {
                // Half the height at most goes to the board, so that on a
                // small phone the moves keep room for four rows.
                let side = min(proxy.size.width, sizeClass == .regular ? 560 : .infinity, max(220, proxy.size.height * 0.5))
                VStack(spacing: 0) {
                    board.frame(width: side, height: side)
                    panel
                }
                .frame(maxWidth: .infinity)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Train") { training = request(nil) }
                    .cdFont(.bodyStrong)
                    .disabled(model.tree.isEmpty)
                menu
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .tree: RepertoireTreeSheet(model: model)
            case .note: RepertoireNoteSheet(model: model)
            case .importPGN: RepertoireImportSheet(model: model)
            }
        }
        .sheet(isPresented: $model.showsPremium) { PremiumSheet() }
        .navigationDestination(isPresented: $showsGames) {
            RepertoireAdherenceScreen(id: model.id, name: model.detail?.name ?? "", side: model.side)
        }
        .fullScreenCover(item: $training, onDismiss: { Task { await model.refresh() } }) {
            RepertoireTrainerScreen(request: $0)
        }
        .confirmationDialog(
            "Replace the moves of this repertoire with the openings you play as \(sideName)?",
            isPresented: $confirmsSeed, titleVisibility: .visible
        ) {
            Button("Replace the tree", role: .destructive) { Task { await model.seedFromGames() } }
        }
        .alert("Rename this repertoire", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Rename") { Task { await model.rename(newName) } }
            Button("Cancel", role: .cancel) {}
        }
        #if DEBUG
            .onAppear {
                if let debug = RepertoireDebug.sheet { sheet = debug }
                if RepertoireDebug.opensTraining { training = request(RepertoireDebug.trainingMode) }
                if RepertoireDebug.opensGames { showsGames = true }
            }
        #endif
    }

    private var sideName: String { model.side == .white ? "White" : "Black" }

    private func request(_ mode: SessionMode?) -> RepertoireTrainingRequest {
        RepertoireTrainingRequest(id: model.id, name: model.detail?.name ?? "", mode: mode)
    }

    // MARK: Board

    private var board: some View {
        BoardView(
            position: model.position,
            orientation: model.orientation,
            lastMove: model.lastMove,
            movableSide: model.movableSide,
            onMove: { model.play($0) }
        )
    }

    // MARK: Panel

    private var panel: some View {
        VStack(spacing: 0) {
            RepertoireLineStrip(model: model)
            CDHairline()
            RepertoireMoveList(model: model)
            CDHairline()
            actions
        }
        .background(CD.canvas)
    }

    /// Five actions under the thumb.
    private var actions: some View {
        HStack(spacing: 0) {
            action("Back", "chevron.backward", enabled: model.canGoBack) { model.goBack() }
            action("Next", "chevron.forward", enabled: model.canGoForward) { model.goForward() }
            action("Tree", "list.bullet.indent", enabled: !model.tree.isEmpty) { sheet = .tree }
            action("Note", "text.bubble", enabled: model.isEditable && !model.isWriting) { sheet = .note }
            action("Remove", "trash", enabled: model.isEditable && model.canGoBack) { askRemoval() }
        }
        .padding(.horizontal, CD.Space.s8)
        .background(CD.surface1)
        // Asked where the thumb already is.
        .confirmationDialog(removalTitle, isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await model.removeCurrentMove() } }
        }
    }

    private func action(_ title: String, _ symbol: String, enabled: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .frame(height: 22)
                Text(title)
                    .font(.custom("Geist-Medium", size: 11, relativeTo: .caption2))
            }
            .foregroundStyle(enabled ? CD.ink2 : CD.ink4.opacity(0.55))
            .frame(maxWidth: .infinity, minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(CDPressStyle())
        .disabled(!enabled)
        .accessibilityLabel(accessibilityName(title))
    }

    private func accessibilityName(_ title: String) -> String {
        switch title {
        case "Back": "Back one move"
        case "Next": "Next move of the main line"
        case "Tree": "The whole move tree"
        case "Note": model.currentNode.map { "Note on \($0.san)" } ?? "Note before the first move"
        default: model.currentNode.map { "Remove \($0.san)" } ?? "Remove"
        }
    }

    private var removalTitle: String {
        guard let node = model.currentNode else { return "" }
        let below = node.descendantCount
        let name = RepertoireTree.numbered(node)
        if below == 0 { return "Remove \(name)?" }
        return below == 1 ? "Remove \(name) and the move after it?" : "Remove \(name) and the \(CDFormat.count(below)) moves after it?"
    }

    /// A move with nothing after it goes at once: it is the way to take back
    /// a move added by mistake. A branch asks first.
    private func askRemoval() {
        guard let node = model.currentNode else { return }
        if node.children.isEmpty {
            Task { await model.removeCurrentMove() }
        } else {
            confirmsRemoval = true
        }
    }

    // MARK: Menu

    private var menu: some View {
        Menu {
            Section {
                Button("Learn new lines", systemImage: "book") { training = request(.learn) }
                Button("Review due moves", systemImage: "arrow.clockwise") { training = request(.review) }
                Button("Games against this repertoire", systemImage: "flag.checkered") { showsGames = true }
            }
            Section {
                Button("Flip the board", systemImage: "arrow.up.arrow.down") { model.flipped.toggle() }
                if let pgn = model.detail?.pgn, !pgn.isEmpty {
                    ShareLink(item: pgn) { Label("Export the PGN", systemImage: "square.and.arrow.up") }
                }
            }
            if model.isEditable {
                Section {
                    Button("Import a PGN", systemImage: "square.and.arrow.down") { sheet = .importPGN }
                    Button("Start from my games", systemImage: "chart.bar") { confirmsSeed = true }
                    Button("Rename", systemImage: "pencil") {
                        newName = model.detail?.name ?? ""
                        renaming = true
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(width: 36, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More")
    }
}

enum BuilderSheet: String, Identifiable {
    case tree, note, importPGN

    var id: String { rawValue }
}

// MARK: The current line

/// The line from the start to the current move, then the main continuation
/// dimmed: one row that follows the current move. Tap a move to stand on it.
private struct RepertoireLineStrip: View {
    let model: RepertoireBuilderModel

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    start
                    let line = model.line
                    ForEach(Array(line.enumerated()), id: \.element.path) { index, entry in
                        if let number = RepertoireTree.number(ply: entry.node.ply, opensRow: index == 0) {
                            Text(number)
                                .cdFont(.meta)
                                .foregroundStyle(CD.ink4)
                                .cdNumber()
                                .padding(.leading, CD.Space.s6)
                                .accessibilityHidden(true)
                        }
                        chip(entry.node, path: entry.path, isAhead: entry.isAhead)
                            .id(entry.path)
                    }
                    if let pending = model.pending {
                        Text(pending.san)
                            .cdFont(.san)
                            .foregroundStyle(CD.ink3)
                            .padding(.horizontal, 7)
                            .frame(height: 30)
                            .id(pending.path)
                    }
                }
                .padding(.horizontal, CD.Space.s12)
            }
            .frame(height: 46)
            .onChange(of: model.shownPath, initial: true) { _, path in
                withAnimation(CD.Motion.state) { reader.scrollTo(path, anchor: .center) }
            }
        }
    }

    private var start: some View {
        Button {
            model.goToStart()
        } label: {
            Image(systemName: "arrow.backward.to.line")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(model.path.isEmpty ? CD.ink : CD.ink3)
                .frame(width: 34, height: 30)
                .background(
                    model.path.isEmpty && model.pending == nil ? CD.accentSoft : .clear,
                    in: RoundedRectangle(cornerRadius: CD.Radius.sm, style: .continuous)
                )
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(CDPressStyle())
        .id([String]())
        .accessibilityLabel("Start position")
    }

    private func chip(_ node: RepertoireNode, path: [String], isAhead: Bool) -> some View {
        let isCurrent = path == model.path && model.pending == nil
        return Button {
            model.goTo(path)
        } label: {
            Text(node.san + RepertoireTree.glyph(node.nags))
                .cdFont(.san)
                .foregroundStyle(isCurrent ? CD.ink : isAhead ? CD.ink4 : CD.ink2)
                .padding(.horizontal, 7)
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
        .accessibilityLabel(RepertoireTree.numbered(node))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

// MARK: The moves of the position

private struct RepertoireMoveList: View {
    @Bindable var model: RepertoireBuilderModel

    var body: some View {
        let moves = model.moves
        let own = moves.filter(\.inRepertoire)
        let others = moves.filter { !$0.inRepertoire }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                if let notice = model.notice { noticeRow(notice) }
                if let detail = model.detail, !detail.editable { readOnly }
                if !own.isEmpty {
                    caption("In your repertoire")
                    ForEach(own) { RepertoireMoveRow(move: $0, model: model) }
                }
                switch model.statsPhase {
                case .loading:
                    HStack(spacing: CD.Space.s12) {
                        ProgressView().tint(CD.ink3)
                        Text("Looking up what is played here").cdFont(.small).foregroundStyle(CD.ink3)
                    }
                    .padding(.horizontal, CD.Space.s16)
                    .frame(minHeight: 52)
                case let .failed(message):
                    VStack(alignment: .leading, spacing: CD.Space.s8) {
                        Text(message).cdFont(.small).foregroundStyle(CD.ink2).fixedSize(horizontal: false, vertical: true)
                        Button("Try again") { model.retryStats() }.buttonStyle(.cd(.secondary, size: .small))
                    }
                    .padding(CD.Space.s16)
                case .loaded:
                    if !others.isEmpty {
                        caption(othersTitle)
                        ForEach(others) { RepertoireMoveRow(move: $0, model: model) }
                    } else if own.isEmpty {
                        Text(emptyText)
                            .cdFont(.small)
                            .foregroundStyle(CD.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(CD.Space.s16)
                    }
                    if let advice = model.stats?.advice { adviceRow(advice) }
                }
                footer
            }
            .padding(.bottom, CD.Space.s16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// Whose move it is, and where the numbers come from.
    private var header: some View {
        HStack(spacing: CD.Space.s8) {
            SideSwatch(side: model.position.turn, size: 10)
            Text(model.isOpponentToMove ? "Your opponent's reply" : "Your move")
                .cdFont(.cardTitle)
                .foregroundStyle(CD.ink)
            Spacer(minLength: CD.Space.s8)
            Menu {
                Picker("Numbers from", selection: $model.source) {
                    ForEach(StatsSource.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                if model.source == .players, !model.ratingBands.isEmpty {
                    Section("Rating of the players") {
                        ForEach(model.ratingBands, id: \.ratings) { band in
                            Button {
                                model.choose(ratings: band.ratings)
                            } label: {
                                if band.ratings == (model.stats?.ratings ?? model.ratings) {
                                    Label(band.label, systemImage: "checkmark")
                                } else {
                                    Text(band.label)
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: CD.Space.s4) {
                    Text(sourceLabel).cdFont(.small).cdNumber()
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(CD.ink2)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Numbers from \(sourceLabel)")
        }
        .padding(.horizontal, CD.Space.s16)
    }

    private var sourceLabel: String {
        if model.source == .players, let band = model.ratingLabel { return "Players \(band)" }
        return model.source.label
    }

    private var othersTitle: String {
        guard model.isOpponentToMove else { return model.source == .mine ? "What you played here" : "Also played here" }
        let unanswered = model.unanswered
        let base = model.source == .mine ? "What your opponents played" : "Other replies"
        return unanswered > 0 ? "\(base) · \(unanswered) not answered yet" : base
    }

    private var emptyText: String {
        let base = model.source == .mine ? "None of your games reached this position." : "No games reach this position."
        return model.isEditable ? "\(base) Play a move on the board to add it." : base
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .cdFont(.meta)
            .foregroundStyle(CD.ink3)
            .padding(.horizontal, CD.Space.s16)
            .padding(.top, CD.Space.s8)
            .padding(.bottom, CD.Space.s4)
            .accessibilityAddTraits(.isHeader)
    }

    private func noticeRow(_ notice: RepertoireBuilderModel.Notice) -> some View {
        HStack(alignment: .top, spacing: CD.Space.s8) {
            Text(notice.text)
                .cdFont(.small)
                .foregroundStyle(notice.isError ? CD.loss : CD.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                model.notice = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CD.ink3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, CD.Space.s12)
        .padding(.vertical, CD.Space.s4)
        .background(CD.surface2, in: RoundedRectangle(cornerRadius: CD.Radius.md, style: .continuous))
        .hairline(notice.isError ? CD.loss.opacity(0.4) : CD.lineStrong, radius: CD.Radius.md)
        .padding(.horizontal, CD.Space.s12)
        .padding(.bottom, CD.Space.s8)
    }

    private var readOnly: some View {
        VStack(alignment: .leading, spacing: CD.Space.s8) {
            Text("This repertoire is kept for reading and export. Your first repertoire stays free to build and train.")
                .cdFont(.small)
                .foregroundStyle(CD.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Button("See Premium") { model.showsPremium = true }
                .buttonStyle(.cd(.secondary, size: .small))
        }
        .padding(CD.Space.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CD.surface1, in: RoundedRectangle(cornerRadius: CD.Radius.md, style: .continuous))
        .hairline(radius: CD.Radius.md)
        .padding(.horizontal, CD.Space.s12)
        .padding(.bottom, CD.Space.s8)
    }

    /// The server's word on the depth of the line.
    private func adviceRow(_ advice: RepertoirePosition.Advice) -> some View {
        HStack(alignment: .top, spacing: CD.Space.s12) {
            Circle()
                .fill(advice.kind == "stop" ? CD.accent : advice.kind == "consider" ? CD.caution : CD.ink4)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: CD.Space.s2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(advice.title).cdFont(.cardTitle).foregroundStyle(CD.ink)
                    Spacer()
                    Text("move \(advice.moveNumber)").cdFont(.meta).foregroundStyle(CD.ink3).cdNumber()
                }
                Text(advice.detail)
                    .cdFont(.small)
                    .foregroundStyle(CD.ink2)
                    .cdNumber()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(CD.Space.s12)
        .background(CD.surface1, in: RoundedRectangle(cornerRadius: CD.Radius.md, style: .continuous))
        .hairline(radius: CD.Radius.md)
        .padding(.horizontal, CD.Space.s12)
        .padding(.top, CD.Space.s12)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var footer: some View {
        if let detail = model.detail {
            let size = "\(CDFormat.plural(detail.moves, "move")), \(CDFormat.plural(detail.lines, "line"))"
            Text(detail.lineLimit.map { "\(size). The free plan holds \(CDFormat.count($0)) lines." } ?? "\(size).")
                .cdFont(.meta)
                .foregroundStyle(CD.ink4)
                .cdNumber()
                .padding(.horizontal, CD.Space.s16)
                .padding(.top, CD.Space.s12)
        }
    }
}

/// One move: its name, how often it is played, how it scores. A move of the
/// repertoire is walked into; another one is added, then walked into.
private struct RepertoireMoveRow: View {
    let move: BuilderMove
    let model: RepertoireBuilderModel

    private var canPlay: Bool {
        move.uci != nil && !model.isWriting && (move.inRepertoire || model.isEditable)
    }

    var body: some View {
        Button {
            if let uci = move.uci { model.play(uci: uci) }
        } label: {
            HStack(spacing: CD.Space.s12) {
                Image(systemName: move.inRepertoire ? "checkmark" : "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(move.inRepertoire ? CD.accent : canPlay ? CD.ink3 : .clear)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: CD.Space.s8) {
                        Text(move.san + move.glyph)
                            .cdFont(.san)
                            .foregroundStyle(CD.ink)
                        if move.hasNote {
                            Image(systemName: "text.bubble")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(CD.ink3)
                                .accessibilityHidden(true)
                        }
                        if move.isUnanswered {
                            CDBadge(text: "Not answered", tone: .accent)
                        }
                        Text(detail)
                            .cdFont(.meta)
                            .foregroundStyle(CD.ink3)
                            .lineLimit(1)
                            .cdNumber()
                        Spacer(minLength: 0)
                        if let stat = move.stat {
                            Text("\(Int((stat.frequency * 100).rounded()))%")
                                .cdFont(.small)
                                .foregroundStyle(CD.ink2)
                                .cdNumber()
                        }
                    }
                    if let stat = move.stat {
                        HStack(spacing: CD.Space.s8) {
                            CDMeter(value: stat.frequency, tint: move.inRepertoire ? CD.accent : CD.ink4, height: 4)
                            ResultBar(first: stat.first, draws: stat.draws, last: stat.last, isMine: stat.isMine)
                                .frame(width: 64)
                        }
                    }
                }
                if move.inRepertoire {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CD.ink4)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, CD.Space.s16)
            .frame(minHeight: 52)
            .background(move.inRepertoire ? CD.surface1 : .clear)
            .contentShape(Rectangle())
            // One sentence for the row; the button around it stays a button.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
        }
        .buttonStyle(CDPressStyle())
        .disabled(!canPlay)
        .accessibilityHint(move.inRepertoire ? "Goes to this move" : canPlay ? "Adds this move to your repertoire" : "")
    }

    /// The opening's name for a move that is played; what follows for a move
    /// of the repertoire.
    private var detail: String {
        if move.inRepertoire {
            return move.movesBelow == 0 ? "end of the line" : "\(CDFormat.plural(move.movesBelow, "move")) after it"
        }
        return move.stat?.opening ?? ""
    }

    private var spoken: String {
        var parts = [move.san + (move.inRepertoire ? ", in your repertoire" : "")]
        if move.isUnanswered { parts.append("not answered yet") }
        if let stat = move.stat {
            parts.append("played \(Int((stat.frequency * 100).rounded())) percent of the time")
            let total = max(1, stat.first + stat.draws + stat.last)
            let share = Int((Double(stat.first) / Double(total) * 100).rounded())
            parts.append(stat.isMine ? "you won \(share) percent" : "White wins \(share) percent")
        }
        return parts.joined(separator: ", ")
    }
}

/// Results as one bar. By colour for a reference database (White, draws,
/// Black: neutral inks, as in the builder of the site); from the player's
/// side for their own games (wins, draws, losses: the outcome colours).
struct ResultBar: View {
    let first: Int
    let draws: Int
    let last: Int
    var isMine = false
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            let total = CGFloat(max(1, first + draws + last))
            HStack(spacing: 0) {
                Rectangle().fill(isMine ? CD.win : CD.ink2).frame(width: proxy.size.width * CGFloat(first) / total)
                Rectangle().fill(isMine ? CD.surface4 : CD.ink4).frame(width: proxy.size.width * CGFloat(draws) / total)
                Rectangle().fill(isMine ? CD.loss : CD.surface3)
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}
