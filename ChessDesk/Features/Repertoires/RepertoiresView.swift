import ChessCore
import SwiftUI

/// Routes of the repertoire screens.
enum RepertoireRoute: Hashable {
    case builder(id: String, name: String)
}

/// "Repertoires": the openings the player chose to play, what is due in
/// them, and the way into the builder and the trainer. A working screen:
/// a figure, rows, no ornament.
struct RepertoiresView: View {
    @Environment(AppModel.self) private var app
    @State private var model: RepertoiresModel?
    @State private var signIn: SignInView.Mode?
    @State private var showsNew = false
    @State private var training: RepertoireTrainingRequest?
    @State private var renaming: RepertoireCard?
    @State private var deleting: RepertoireCard?
    @State private var newName = ""
    @State private var opened: RepertoireRoute?
    @State private var loadedRevision: Int?

    var body: some View {
        Group {
            if app.playerToken == nil {
                guest
            } else if let model {
                content(model)
            } else {
                LoadingView()
            }
        }
        .navigationTitle("Repertoires")
        .navigationBarTitleDisplayMode(.inline)
        // The page carries its own title, in the serif; the bar keeps the name
        // for the back button of the screens pushed from here.
        .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) } }
        .cdPage()
        // Runs when the screen appears, also on the way back from the
        // builder: the same account keeps its model and reads the list again.
        .task(id: app.accountRevision) {
            guard let token = app.playerToken else {
                model = nil
                return
            }
            if let model, loadedRevision == app.accountRevision {
                await model.load()
                return
            }
            let fresh = RepertoiresModel(api: app.api, token: token, onUnauthorized: { app.sessionExpired() })
            model = fresh
            loadedRevision = app.accountRevision
            await fresh.load()
            #if DEBUG
                openDebugRoute()
            #endif
        }
        .sheet(item: $signIn) { SignInView(mode: $0) }
        // Pushed from state, not from a value link: the screen works wherever
        // it is hung, in a stack with a path or without.
        .navigationDestination(item: $opened) { route in
            switch route {
            case let .builder(id, name): RepertoireBuilderScreen(id: id, name: name)
            }
        }
    }

    #if DEBUG
        private func openDebugRoute() {
            guard !RepertoireDebug.consumed, let route = DebugLaunch.route, route.first == "repertoires" else { return }
            RepertoireDebug.consumed = true
            guard route.count > 1 else { return }
            if route[1] == "new" {
                showsNew = true
            } else {
                let name = model?.repertoires.first { $0.id == route[1] }?.name ?? ""
                opened = .builder(id: route[1], name: name)
            }
        }
    #endif

    // MARK: Guest

    private var title: some View {
        Text("Repertoires")
            .cdFont(.display)
            .foregroundStyle(CD.ink)
            .accessibilityAddTraits(.isHeader)
    }

    private var guest: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s24) {
              title
              CDCard(tone: .raised, padding: CD.Space.s20) {
                VStack(alignment: .leading, spacing: CD.Space.s12) {
                    Text("Build your opening repertoire")
                        .cdFont(.plateTitle)
                        .foregroundStyle(CD.ink)
                    Text("Pick the moves you want to play, prepare an answer to every reply, then train them so they hold up in your games. A repertoire belongs to an account.")
                        .cdFont(.lede)
                        .foregroundStyle(CD.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Create an account") { signIn = .createAccount }
                        .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
                        .padding(.top, CD.Space.s4)
                    Button("Sign in") { signIn = .signIn }
                        .buttonStyle(.cd(.secondary, size: .large, fullWidth: true))
                }
              }
            }
            .page()
        }
    }

    // MARK: Signed in

    @ViewBuilder private func content(_ model: RepertoiresModel) -> some View {
        @Bindable var model = model
        switch model.phase {
        case .loading:
            LoadingView()
        case let .failed(message):
            LoadFailureView(title: "Your repertoires did not load", message: message) {
                Task { await model.load() }
            }
        case .ready:
            ScrollView {
                VStack(alignment: .leading, spacing: CD.Space.s24) {
                    title
                    if let notice = model.notice {
                        Text(notice)
                            .cdFont(.small)
                            .foregroundStyle(CD.loss)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if model.repertoires.isEmpty {
                        empty(model)
                    } else {
                        if let list = model.list { due(list, top: model.top) }
                        VStack(alignment: .leading, spacing: CD.Space.s12) {
                            SectionHeader(title: "My repertoires")
                            rows(model)
                        }
                        create(model)
                    }
                }
                .page()
            }
            .refreshable { await model.load() }
            .sheet(isPresented: $showsNew) {
                NewRepertoireSheet(model: model) { created in
                    opened = .builder(id: created.id, name: created.name)
                }
            }
            .sheet(isPresented: $model.showsPremium) { PremiumSheet() }
            .fullScreenCover(item: $training, onDismiss: { Task { await model.load() } }) {
                RepertoireTrainerScreen(request: $0)
            }
            .alert("Rename this repertoire", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Rename") {
                    if let repertoire = renaming { Task { await model.rename(repertoire, to: newName) } }
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                deleting.map { "Delete \($0.name)? Its moves go; what you learned of them stays with you." } ?? "",
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let repertoire = deleting { Task { await model.delete(repertoire) } }
                }
            }
        }
    }

    /// What is due across the repertoires, and the one action.
    private func due(_ list: RepertoireList, top: RepertoireCard?) -> some View {
        CDCard(tone: .raised, padding: CD.Space.s20) {
            VStack(alignment: .leading, spacing: CD.Space.s12) {
                Text("Due today")
                    .cdFont(.small)
                    .foregroundStyle(CD.ink3)
                HStack(alignment: .firstTextBaseline, spacing: CD.Space.s8) {
                    Text(CDFormat.count(list.totalDue))
                        .cdFont(.metric)
                        .foregroundStyle(CD.ink)
                        .cdNumber()
                    Text("\(list.totalDue == 1 ? "move" : "moves") across \(CDFormat.plural(list.repertoires.count, "repertoire"))")
                        .cdFont(.body)
                        .foregroundStyle(CD.ink3)
                }
                .accessibilityElement(children: .combine)
                Text(dueSentence(list, top: top))
                    .cdFont(.meta)
                    .foregroundStyle(CD.ink3)
                    .cdNumber()
                    .fixedSize(horizontal: false, vertical: true)
                if let top, top.editable, top.moves > 0 {
                    Button(list.totalDue > 0 ? "Review now" : "Train now") {
                        training = RepertoireTrainingRequest(id: top.id, name: top.name)
                    }
                    .buttonStyle(.cd(list.totalDue > 0 ? .primary : .secondary, fullWidth: true))
                }
            }
        }
    }

    private func dueSentence(_ list: RepertoireList, top: RepertoireCard?) -> String {
        if list.totalDue > 0, let top { return "Start with \(top.name): \(CDFormat.count(top.progress.dueMoves)) due." }
        if list.repertoires.contains(where: { $0.progress.newLines > 0 }) {
            return "Nothing due. Learn a few new lines meanwhile."
        }
        return "Nothing due. Moves come back as their interval ends."
    }

    private func rows(_ model: RepertoiresModel) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(model.repertoires.enumerated()), id: \.element.id) { index, repertoire in
                if index > 0 { CDHairline() }
                HStack(spacing: 0) {
                    Button {
                        opened = .builder(id: repertoire.id, name: repertoire.name)
                    } label: {
                        RepertoireRow(repertoire: repertoire)
                    }
                    .buttonStyle(CDPressStyle())
                    Menu {
                        if repertoire.editable {
                            Button("Train", systemImage: "target") {
                                training = RepertoireTrainingRequest(id: repertoire.id, name: repertoire.name)
                            }
                            Button("Rename", systemImage: "pencil") {
                                newName = repertoire.name
                                renaming = repertoire
                            }
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = repertoire }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(CD.ink3)
                            .frame(width: 48, height: 60)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Actions for \(repertoire.name)")
                }
            }
        }
        .cardSurface()
        .hairline()
    }

    @ViewBuilder private func create(_ model: RepertoiresModel) -> some View {
        if model.list?.canCreate == true {
            Button("New repertoire") { showsNew = true }
                .buttonStyle(.cd(.secondary, fullWidth: true))
        } else {
            // The server says another one cannot be created: the free plan holds one.
            CDCard {
                VStack(alignment: .leading, spacing: CD.Space.s12) {
                    HStack(spacing: CD.Space.s8) {
                        CDBadge(text: "Premium", tone: .premium)
                        Text("A repertoire for every opening you play")
                            .cdFont(.cardTitle)
                            .foregroundStyle(CD.ink)
                    }
                    Text("The free plan holds one repertoire, with up to 20 lines and full training. Premium adds as many repertoires and lines as you like.")
                        .cdFont(.small)
                        .foregroundStyle(CD.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("See Premium") { model.showsPremium = true }
                        .buttonStyle(.cd(.secondary, fullWidth: true))
                }
            }
        }
    }

    private func empty(_ model: RepertoiresModel) -> some View {
        CDCard(tone: .raised, padding: CD.Space.s20) {
            VStack(alignment: .leading, spacing: CD.Space.s12) {
                Text("Build your opening repertoire")
                    .cdFont(.plateTitle)
                    .foregroundStyle(CD.ink)
                Text("Pick the moves you want to play, prepare an answer to every reply, then let ChessDesk quiz you on them at the right moment.")
                    .cdFont(.lede)
                    .foregroundStyle(CD.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: CD.Space.s8) {
                    point("Start from the openings you already play in your imported games")
                    point("Train each line with spaced repetition, a few minutes a day")
                    point("See where your real games left your preparation")
                }
                if model.list?.canCreate == true {
                    Button("New repertoire") { showsNew = true }
                        .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
                        .padding(.top, CD.Space.s4)
                }
                Text("Your first repertoire is free, with up to 20 lines and full training.")
                    .cdFont(.meta)
                    .foregroundStyle(CD.ink3)
            }
        }
    }

    private func point(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: CD.Space.s8) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CD.accent)
                .accessibilityHidden(true)
            Text(text)
                .cdFont(.small)
                .foregroundStyle(CD.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private extension View {
    func page() -> some View {
        pageGutter()
            .padding(.top, CD.Space.s8)
            .padding(.bottom, CD.Space.s56)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
    }
}

/// One repertoire: its colour, its size, how much of it is learned, what is due.
private struct RepertoireRow: View {
    let repertoire: RepertoireCard

    var body: some View {
        let status = repertoire.status
        HStack(alignment: .center, spacing: CD.Space.s12) {
            SideSwatch(side: repertoire.side, size: 11)
            VStack(alignment: .leading, spacing: CD.Space.s6) {
                HStack(alignment: .firstTextBaseline, spacing: CD.Space.s8) {
                    Text(repertoire.name)
                        .cdFont(.bodyStrong)
                        .foregroundStyle(CD.ink)
                        .lineLimit(1)
                    Spacer(minLength: CD.Space.s8)
                    Text(status.text)
                        .cdFont(.small)
                        .foregroundStyle(status.isDue ? CD.accentStrong : CD.ink3)
                        .cdNumber()
                        .lineLimit(1)
                }
                HStack(spacing: CD.Space.s8) {
                    Text(detail)
                        .cdFont(.meta)
                        .foregroundStyle(CD.ink3)
                        .cdNumber()
                        .lineLimit(1)
                        .layoutPriority(1)
                    CDMeter(value: repertoire.learnedShare)
                }
            }
        }
        .padding(.leading, CD.Space.s16)
        .padding(.vertical, CD.Space.s12)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(repertoire.name), \(detail), \(Int((repertoire.learnedShare * 100).rounded())) percent learned, \(status.text)")
    }

    private var detail: String {
        let side = repertoire.side == .white ? "White" : "Black"
        if !repertoire.editable { return "\(side) · kept for reading" }
        return repertoire.progress.moves > 0
            ? "\(side) · \(CDFormat.plural(repertoire.progress.moves, "move")) to know" : "\(side) · no moves yet"
    }
}

/// A name and a side: the two things a new repertoire needs.
private struct NewRepertoireSheet: View {
    let model: RepertoiresModel
    let onCreated: (RepertoireDetail) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color = "WHITE"
    @State private var error: String?
    @State private var isWorking = false
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s20) {
                Text("New repertoire")
                    .cdFont(.plateTitle)
                    .foregroundStyle(CD.ink)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: CD.Space.s6) {
                    Text("Name").cdFont(.small).foregroundStyle(CD.ink2)
                    TextField("", text: $name, prompt: Text("For example, Caro-Kann").foregroundStyle(CD.ink4))
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(create)
                        .cdFont(.body)
                        .foregroundStyle(CD.ink)
                        .padding(.horizontal, CD.Space.s12)
                        .frame(minHeight: 48)
                        .background(CD.surface3, in: RoundedRectangle(cornerRadius: CD.Radius.md, style: .continuous))
                        .hairline(CD.lineStrong, radius: CD.Radius.md)
                }
                VStack(alignment: .leading, spacing: CD.Space.s6) {
                    Text("You play").cdFont(.small).foregroundStyle(CD.ink2)
                    CDSegmented(options: [(value: "WHITE", label: "White"), (value: "BLACK", label: "Black")], selection: $color)
                }
                if let error {
                    Text(error)
                        .cdFont(.small)
                        .foregroundStyle(CD.loss)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: CD.Space.s8) {
                    Button(action: create) {
                        if isWorking { ProgressView().tint(CD.accentInk) } else { Text("Create") }
                    }
                    .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
                    .disabled(isWorking)
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { focused = true }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = "Name your repertoire first."
            return
        }
        guard !isWorking else { return }
        isWorking = true
        error = nil
        Task {
            defer { isWorking = false }
            do {
                let created = try await model.create(name: trimmed, color: color)
                dismiss()
                onCreated(created)
            } catch let failure as APIError {
                error = failure.message
                if failure.isPremiumRequired { dismiss() }
            } catch {
                self.error = APIError.unreadable.message
            }
        }
    }
}
