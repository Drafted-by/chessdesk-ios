import SwiftUI

/// The positions behind one recurring pattern (the site's
/// `/train/pattern/[key]`), drilled with the mistakes trainer: each result
/// counts towards the mistake's own schedule, as on the site.
struct PatternDrillScreen: View {
    let key: String
    let close: () -> Void

    @Environment(AppModel.self) private var app

    var body: some View {
        Loadable(
            id: AnyHashable(key),
            failureTitle: "This drill did not load",
            load: {
                guard let token = app.token else { throw APIError.server(status: 401, code: "unauthorized", message: "Sign in to continue.") }
                return try await app.api.patternDrill(key: key, token: token)
            },
            content: { drill in
                if drill.mistakes.isEmpty {
                    LoadFailureView(
                        title: "Nothing to drill here",
                        message: "The positions of this pattern are all mastered, or no longer in your games."
                    )
                } else {
                    VStack(spacing: 0) {
                        Text(drill.title)
                            .cdFont(.cardTitle)
                            .foregroundStyle(CD.ink)
                            .lineLimit(1)
                            .padding(.horizontal, 56)
                            .frame(height: 44)
                            .accessibilityAddTraits(.isHeader)
                        MistakeSession(mistakes: drill.mistakes, close: close)
                    }
                }
            }
        )
        .overlay(alignment: .topLeading) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CD.ink2)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Close")
            .padding(.leading, CD.Space.s4)
        }
        .background(CD.canvas.ignoresSafeArea())
    }
}
