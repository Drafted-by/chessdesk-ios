import SwiftUI
import UIKit

@main
struct ChessDeskApp: App {
    @State private var app: AppModel
    @State private var narration = NarrationPlayer()

    init() {
        Appearance.apply()
        let app = AppModel()
        app.judge = EngineJudge()
        _app = State(initialValue: app)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(narration)
                .preferredColorScheme(.dark)
                .tint(CD.accent)
                .task { await app.restoreSession() }
        }
    }
}

/// UIKit chrome in the ChessDesk voice: serif titles on the canvas, a quiet
/// tab bar where only the current section is brass.
enum Appearance {
    static func apply() {
        let ink = UIColor(CD.ink)
        let canvas = UIColor(CD.canvas)

        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = canvas
        navigation.shadowColor = .clear
        navigation.titleTextAttributes = [
            .font: UIFont(name: "Geist-SemiBold", size: 16) ?? .systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: ink,
        ]
        navigation.largeTitleTextAttributes = [
            .font: UIFont(name: "Newsreader72pt-Medium", size: 34) ?? .systemFont(ofSize: 34, weight: .medium),
            .foregroundColor: ink,
        ]
        let scrolled = navigation.copy()
        scrolled.shadowColor = UIColor(CD.line)
        UINavigationBar.appearance().standardAppearance = scrolled
        UINavigationBar.appearance().compactAppearance = scrolled
        UINavigationBar.appearance().scrollEdgeAppearance = navigation

        let tabs = UITabBarAppearance()
        tabs.configureWithOpaqueBackground()
        tabs.backgroundColor = UIColor(CD.surface1)
        tabs.shadowColor = UIColor(CD.lineStrong)
        let labelFont = UIFont(name: "Geist-Medium", size: 10.5) ?? .systemFont(ofSize: 10.5, weight: .medium)
        for item in [tabs.stackedLayoutAppearance, tabs.inlineLayoutAppearance, tabs.compactInlineLayoutAppearance] {
            item.normal.iconColor = UIColor(CD.ink3)
            item.normal.titleTextAttributes = [.font: labelFont, .foregroundColor: UIColor(CD.ink3)]
            item.selected.iconColor = UIColor(CD.accent)
            item.selected.titleTextAttributes = [.font: labelFont, .foregroundColor: UIColor(CD.accentStrong)]
        }
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().scrollEdgeAppearance = tabs
    }
}
