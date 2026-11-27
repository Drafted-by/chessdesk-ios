import ChessCore
import SwiftUI

/// A learning path: what it does for the player, where they stand, and its
/// modules, each a chapter with its stages. The lead action starts or
/// continues the path.
struct PathView: View {
    let slug: String

    @Environment(AppModel.self) private var app
    @State private var stage: StageRequest?
    @State private var showsPremium = false
    @State private var reload = 0

    var body: some View {
        Loadable(
            id: AnyHashable([AnyHashable(slug), AnyHashable(app.backend), AnyHashable(app.accountRevision), AnyHashable(reload)]),
            failureTitle: "This course did not load",
            load: { try await app.api.path(slug: slug, token: app.token) },
            content: { path in
                page(PathProgress(path: path, guest: app.isSignedIn ? nil : app.guestProgress))
                #if DEBUG
                    .onAppear {
                        if let wanted = DebugLaunch.opensStage, stage == nil, reload == 0 {
                            stage = StageRequest(path: path.slug, pathTitle: path.title, stage: wanted)
                        }
                        if DebugLaunch.opensPremium, reload == 0 { showsPremium = true }
                    }
                #endif
            }
        )
        .navigationBarTitleDisplayMode(.inline)
        .cdPage()
        .fullScreenCover(item: $stage, onDismiss: { reload += 1 }) { request in
            PathStageScreen(request: request, showPremium: { showsPremium = true })
        }
        .sheet(isPresented: $showsPremium) { PremiumSheet() }
    }

    private func page(_ progress: PathProgress) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s32) {
                PathHero(progress: progress) { open(progress.next, in: progress) }
                PathFacts(progress: progress)
                VStack(alignment: .leading, spacing: CD.Space.s12) {
                    SectionHeader(title: "How it works")
                    Text(progress.path.intro)
                        .cdFont(.body)
                        .foregroundStyle(CD.ink2)
                        .frame(maxWidth: CD.readingWidth, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: CD.Space.s24) {
                    ForEach(Array(progress.path.modules.enumerated()), id: \.element.id) { index, module in
                        if index > 0 { OrnamentRule() }
                        ModuleSection(number: index + 1, module: module, progress: progress) { stage in
                            open(stage, in: progress)
                        }
                    }
                }
            }
            .pageGutter()
            .padding(.top, CD.Space.s8)
            .padding(.bottom, CD.Space.s56)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
    }

    private func open(_ stage: PathDetail.Stage?, in progress: PathProgress) {
        guard let stage else { return }
        if progress.state(of: stage) == .locked {
            showsPremium = true
        } else {
            self.stage = StageRequest(path: progress.path.slug, pathTitle: progress.path.title, stage: stage.slug)
        }
    }
}

/// A path as this viewer sees it. The server knows the progress of an
/// account; a guest's finished stages are on the device and laid over it.
struct PathProgress {
    let path: PathDetail
    let guest: GuestProgress?

    func state(of stage: PathDetail.Stage) -> StageState {
        if stage.state != .locked, guest?.hasCompleted(stage: stage.slug, path: path.slug) == true { return .done }
        return stage.state
    }

    func learned(in stage: PathDetail.Stage) -> Int {
        state(of: stage) == .done ? stage.exercises : stage.learned
    }

    var learned: Int { path.stages.reduce(0) { $0 + learned(in: $1) } }

    /// The first stage open to the viewer and not finished; with none left,
    /// the first Premium stage (the paywall).
    var next: PathDetail.Stage? {
        let stages = path.stages
        return stages.first { [.new, .started].contains(state(of: $0)) } ?? stages.first { $0.state == .locked }
    }

    var hasStarted: Bool { learned > 0 }
    var freeStages: Int { path.stages.count { $0.free } }
}

// MARK: Hero

private struct PathHero: View {
    let progress: PathProgress
    let start: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let layout = sizeClass == .regular
            ? AnyLayout(HStackLayout(alignment: .center, spacing: CD.Space.s32))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: CD.Space.s20))
        layout {
            VStack(alignment: .leading, spacing: CD.Space.s16) {
                VStack(alignment: .leading, spacing: CD.Space.s8) {
                    Emblem(kind: .rating, size: 48)
                        .padding(.bottom, CD.Space.s4)
                    Text("Course · \(progress.path.level)")
                        .cdFont(.small)
                        .foregroundStyle(CD.ink3)
                    Text(progress.path.title)
                        .cdFont(.display)
                        .foregroundStyle(CD.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("The tactics, checkmates and habits that decide games under 1000. One worked example, then positions to solve yourself.")
                        .cdFont(.lede)
                        .foregroundStyle(CD.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: CD.Space.s8) {
                    Button(action: start) {
                        if progress.next?.state == .locked {
                            Label(leadTitle, systemImage: "lock")
                        } else {
                            Text(leadTitle)
                        }
                    }
                    .buttonStyle(.cd(.lead, size: .large, fullWidth: true))
                    Text(caption)
                        .cdFont(.meta)
                        .foregroundStyle(CD.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 420, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            StaticBoardView(fen: progress.path.previewFen, orientation: progress.path.color.side, cornerRadius: CD.Radius.md)
                .frame(maxWidth: sizeClass == .regular ? 300 : .infinity)
        }
        .plate()
    }

    private var leadTitle: String {
        guard let next = progress.next else { return "Every stage is done" }
        if next.state == .locked { return "Open the rest of the course" }
        return progress.hasStarted ? "Continue: \(next.title)" : "Start the first stage"
    }

    private var caption: String {
        guard let next = progress.next else { return "You have worked every exercise of the course." }
        if next.state == .locked {
            return "You have done the \(progress.freeStages) free stages. Premium opens the other \(progress.path.totals.stages - progress.freeStages)."
        }
        return progress.hasStarted
            ? "\(CDFormat.plural(next.exercises, "exercise")) in this stage."
            : "Free, no account needed. About five minutes."
    }
}

private struct PathFacts: View {
    let progress: PathProgress

    var body: some View {
        VStack(alignment: .leading, spacing: CD.Space.s12) {
            HStack(alignment: .top, spacing: 0) {
                fact(CDFormat.count(progress.path.totals.modules), "themes")
                divider
                fact(CDFormat.count(progress.path.totals.stages), "stages")
                divider
                fact(CDFormat.count(progress.path.totals.exercises), "exercises")
            }
            if progress.hasStarted {
                VStack(alignment: .leading, spacing: CD.Space.s6) {
                    CDMeter(value: Double(progress.learned) / Double(max(1, progress.path.totals.exercises)))
                    Text("\(CDFormat.count(progress.learned)) of \(CDFormat.count(progress.path.totals.exercises)) exercises done")
                        .cdFont(.meta)
                        .foregroundStyle(CD.ink3)
                        .cdNumber()
                }
                .padding(.horizontal, CD.Space.s16)
            }
        }
        .padding(.vertical, CD.Space.s16)
        .background(CD.surface1, in: RoundedRectangle(cornerRadius: CD.Radius.lg, style: .continuous))
        .hairline()
    }

    private var divider: some View {
        Rectangle().fill(CD.line).frame(width: 1, height: 40)
    }

    private func fact(_ value: String, _ label: String) -> some View {
        VStack(spacing: CD.Space.s4) {
            Text(value)
                .cdFont(.metricMedium)
                .foregroundStyle(CD.ink)
                .cdNumber()
            Text(label)
                .cdFont(.meta)
                .foregroundStyle(CD.ink3)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Modules

/// A module opens like a chapter: serif numeral, serif title, its position,
/// then its stages.
private struct ModuleSection: View {
    let number: Int
    let module: PathDetail.Module
    let progress: PathProgress
    let open: (PathDetail.Stage) -> Void

    @State private var expanded = false
    private let collapsedCount = 4

    var body: some View {
        VStack(alignment: .leading, spacing: CD.Space.s16) {
            HStack(alignment: .top, spacing: CD.Space.s16) {
                VStack(alignment: .leading, spacing: CD.Space.s6) {
                    Text("\(number)")
                        .font(.custom("Newsreader72pt-Italic", size: 30, relativeTo: .title))
                        .foregroundStyle(CD.ink4)
                        .cdNumber()
                    Text(module.title)
                        .cdFont(.plateTitle)
                        .foregroundStyle(CD.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(module.summary)
                        .cdFont(.small)
                        .foregroundStyle(CD.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let board = module.board {
                    StaticBoardView(fen: board, orientation: progress.path.color.side)
                        .frame(width: 96, height: 96)
                }
            }

            VStack(spacing: 0) {
                let stages = shownStages
                ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                    if index > 0 { CDHairline() }
                    Button { open(stage) } label: {
                        StageRow(stage: stage, state: progress.state(of: stage), learned: progress.learned(in: stage))
                    }
                    .buttonStyle(CDPressStyle())
                }
                if module.stages.count > collapsedCount {
                    CDHairline()
                    Button {
                        withAnimation(CD.Motion.enter) { expanded.toggle() }
                    } label: {
                        HStack {
                            Text(expanded ? "Show fewer" : "All \(module.stages.count) stages")
                                .cdFont(.small)
                                .foregroundStyle(CD.ink2)
                            Spacer()
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(CD.ink4)
                        }
                        .padding(.horizontal, CD.Space.s16)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(CDPressStyle())
                }
            }
            .background(CD.surface1, in: RoundedRectangle(cornerRadius: CD.Radius.lg, style: .continuous))
            .hairline()
        }
    }

    /// Collapsed: the first stages, and always the ones open to the viewer.
    private var shownStages: [PathDetail.Stage] {
        if expanded || module.stages.count <= collapsedCount { return module.stages }
        let open = Set(module.stages.filter { progress.state(of: $0) != .locked }.map(\.slug))
        return module.stages.enumerated().filter { $0.offset < collapsedCount || open.contains($0.element.slug) }.map(\.element)
    }
}

private struct StageRow: View {
    let stage: PathDetail.Stage
    let state: StageState
    let learned: Int

    var body: some View {
        HStack(spacing: CD.Space.s12) {
            VStack(alignment: .leading, spacing: CD.Space.s4) {
                Text(stage.title)
                    .cdFont(.bodyStrong)
                    .foregroundStyle(state == .locked ? CD.ink3 : CD.ink)
                    .multilineTextAlignment(.leading)
                Text(detail)
                    .cdFont(.meta)
                    .foregroundStyle(state == .done ? CD.win : CD.ink3)
                    .cdNumber()
            }
            Spacer(minLength: CD.Space.s8)
            switch state {
            case .locked:
                Image(systemName: "lock")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CD.ink3)
                    .accessibilityLabel("Premium")
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CD.win)
                    .accessibilityHidden(true)
            case .new, .started:
                if stage.free { CDBadge(text: "Free", tone: .accent) }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CD.ink4)
            }
        }
        .padding(.horizontal, CD.Space.s16)
        .padding(.vertical, CD.Space.s12)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    private var detail: String {
        let exercises = CDFormat.plural(stage.exercises, "exercise")
        return switch state {
        case .done: "\(exercises) · done"
        case .started: "\(learned) of \(exercises) done"
        case .new, .locked: exercises
        }
    }
}

/// The card that puts the featured path forward, on Today and above the
/// opening courses. The one brass action of the screen it sits on.
struct FeaturedPathPlate: View {
    let path: PathCard
    let guest: GuestProgress?

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            let layout = sizeClass == .regular
                ? AnyLayout(HStackLayout(alignment: .center, spacing: CD.Space.s24))
                : AnyLayout(VStackLayout(alignment: .leading, spacing: CD.Space.s20))
            layout {
                VStack(alignment: .leading, spacing: CD.Space.s12) {
                    HStack(alignment: .center, spacing: CD.Space.s12) {
                        Emblem(kind: .rating, size: 44)
                        VStack(alignment: .leading, spacing: CD.Space.s2) {
                            Text(started ? "Your course" : "Start here")
                                .cdFont(.small)
                                .foregroundStyle(CD.ink3)
                            Text(path.title)
                                .cdFont(.pageTitle)
                                .foregroundStyle(CD.ink)
                        }
                    }
                    Text("Under 1000, games are lost to a hanging piece or a checkmate nobody saw. This course trains you to see them, one position at a time.")
                        .cdFont(.lede)
                        .foregroundStyle(CD.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    if path.learned > 0 {
                        VStack(alignment: .leading, spacing: CD.Space.s6) {
                            CDMeter(value: Double(path.learned) / Double(max(1, path.totals.exercises)))
                            Text("\(CDFormat.count(path.learned)) of \(CDFormat.count(path.totals.exercises)) exercises done")
                                .cdFont(.meta)
                                .foregroundStyle(CD.ink3)
                                .cdNumber()
                        }
                    } else if guestStages > 0 {
                        Text("\(CDFormat.plural(guestStages, "stage")) done on this device.")
                            .cdFont(.meta)
                            .foregroundStyle(CD.ink3)
                            .cdNumber()
                    }
                    NavigationLink(value: CourseRoute.path(slug: path.slug)) {
                        Text(started ? "Continue the course" : "Start Reach 1000 Elo")
                    }
                    .buttonStyle(.cd(.lead, size: .large, fullWidth: sizeClass != .regular))
                    .padding(.top, CD.Space.s4)
                    if !started {
                        Text("The first stages are free, no account needed.")
                            .cdFont(.meta)
                            .foregroundStyle(CD.ink3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                StaticBoardView(fen: path.previewFen, orientation: path.color.side, cornerRadius: CD.Radius.md)
                    .frame(maxWidth: sizeClass == .regular ? 260 : .infinity)
            }
        }
        .plate()
    }

    /// Stages a guest finished on this device (the server does not know them).
    private var guestStages: Int { guest?.completedStages[path.slug]?.count ?? 0 }

    private var started: Bool { path.learned > 0 || guestStages > 0 }
}
