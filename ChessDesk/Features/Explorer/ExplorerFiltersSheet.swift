import SwiftUI

/// The filters of the explorer, the same ones as on the site: game site, time
/// control, rated or casual, dates, the opponent's rating. They narrow the
/// games; the position being looked at is kept.
struct ExplorerFiltersSheet: View {
    let model: ExplorerModel

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ExplorerFilters()
    @State private var usesFrom = false
    @State private var usesTo = false
    @State private var from = Date.now
    @State private var to = Date.now
    @State private var minimum = ""
    @State private var maximum = ""

    private static let timeLabels = [
        "BULLET": "Bullet", "BLITZ": "Blitz", "RAPID": "Rapid", "CLASSICAL": "Classical", "CORRESPONDENCE": "Daily",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s24) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Filters")
                        .cdFont(.plateTitle)
                        .foregroundStyle(CD.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Clear") { reset(to: draft.cleared) }
                        .buttonStyle(.cd(.ghost))
                }

                group("Site") {
                    CDSegmented(
                        options: [
                            (value: GameProvider?.none, label: "Both"),
                            (value: GameProvider?.some(.chesscom), label: "Chess.com"),
                            (value: GameProvider?.some(.lichess), label: "Lichess"),
                        ],
                        selection: $draft.source
                    )
                }

                group("Time control", detail: draft.timeClasses.isEmpty ? "All" : nil) {
                    RepertoireFlowLayout(spacing: CD.Space.s8) {
                        ForEach(ExplorerFilters.timeClasses, id: \.self) { timeClass in
                            let isOn = draft.timeClasses.contains(timeClass)
                            Button {
                                if isOn { draft.timeClasses.remove(timeClass) } else { draft.timeClasses.insert(timeClass) }
                            } label: {
                                Text(Self.timeLabels[timeClass] ?? timeClass)
                                    .cdFont(.small)
                                    .foregroundStyle(isOn ? CD.ink : CD.ink2)
                                    .padding(.horizontal, CD.Space.s12)
                                    .frame(minHeight: 44)
                                    .background(
                                        isOn ? CD.accentSoft : CD.surface2,
                                        in: RoundedRectangle(cornerRadius: CD.Radius.md, style: .continuous)
                                    )
                                    .hairline(isOn ? CD.accentLine : CD.lineStrong, radius: CD.Radius.md)
                            }
                            .buttonStyle(CDPressStyle())
                            .accessibilityAddTraits(isOn ? .isSelected : [])
                        }
                    }
                }

                group("Games") {
                    CDSegmented(
                        options: [
                            (value: ExplorerFilters.Rated.all, label: "All"),
                            (value: ExplorerFilters.Rated.rated, label: "Rated"),
                            (value: ExplorerFilters.Rated.casual, label: "Casual"),
                        ],
                        selection: $draft.rated
                    )
                }

                group("Played") {
                    VStack(spacing: 0) {
                        dateRow("From", isOn: $usesFrom, date: $from)
                        CDHairline()
                        dateRow("To", isOn: $usesTo, date: $to)
                    }
                    .background(CD.surface1, in: RoundedRectangle(cornerRadius: CD.Radius.md, style: .continuous))
                    .hairline(radius: CD.Radius.md)
                }

                group("Opponent's rating") {
                    HStack(spacing: CD.Space.s8) {
                        ratingField("From", text: $minimum)
                        Text("to").cdFont(.small).foregroundStyle(CD.ink3)
                        ratingField("To", text: $maximum)
                    }
                }

                Button("Show the games") { apply() }
                    .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
            }
            .padding(.horizontal, CD.Space.s24)
            .padding(.top, CD.Space.s32)
            .padding(.bottom, CD.Space.s24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(CD.canvas.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .onAppear { reset(to: model.filters) }
    }

    private func group(_ title: String, detail: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: CD.Space.s8) {
            HStack(alignment: .firstTextBaseline, spacing: CD.Space.s8) {
                Text(title).cdFont(.small).foregroundStyle(CD.ink2)
                if let detail { Text(detail).cdFont(.meta).foregroundStyle(CD.ink4) }
            }
            content()
        }
    }

    private func dateRow(_ title: String, isOn: Binding<Bool>, date: Binding<Date>) -> some View {
        HStack(spacing: CD.Space.s12) {
            Toggle(title, isOn: isOn)
                .cdFont(.body)
                .foregroundStyle(CD.ink)
                .tint(CD.accent)
                .fixedSize()
            Spacer(minLength: 0)
            if isOn.wrappedValue {
                DatePicker(title, selection: date, in: ...Date.now, displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "en_US"))
            }
        }
        .padding(.horizontal, CD.Space.s12)
        .frame(minHeight: 52)
    }

    private func ratingField(_ label: String, text: Binding<String>) -> some View {
        TextField("", text: text, prompt: Text("Any").foregroundStyle(CD.ink4))
            .keyboardType(.numberPad)
            .cdFont(.body)
            .foregroundStyle(CD.ink)
            .cdNumber()
            .padding(.horizontal, CD.Space.s12)
            .frame(minHeight: 48)
            .background(CD.surface3, in: RoundedRectangle(cornerRadius: CD.Radius.md, style: .continuous))
            .hairline(CD.lineStrong, radius: CD.Radius.md)
            .accessibilityLabel("Opponent's rating, \(label.lowercased())")
    }

    private func reset(to filters: ExplorerFilters) {
        draft = filters
        usesFrom = filters.dateFrom != nil
        usesTo = filters.dateTo != nil
        from = filters.dateFrom.flatMap { ExplorerFilters.date(day: $0) } ?? .now
        to = filters.dateTo.flatMap { ExplorerFilters.date(day: $0) } ?? .now
        minimum = filters.opponentMin.map(String.init) ?? ""
        maximum = filters.opponentMax.map(String.init) ?? ""
    }

    private func apply() {
        var filters = draft
        filters.dateFrom = usesFrom ? ExplorerFilters.day(from) : nil
        filters.dateTo = usesTo ? ExplorerFilters.day(to) : nil
        // The API takes ratings from 0 to 4000.
        filters.opponentMin = Int(minimum).map { min(4000, max(0, $0)) }
        filters.opponentMax = Int(maximum).map { min(4000, max(0, $0)) }
        model.apply(filters)
        dismiss()
    }
}
