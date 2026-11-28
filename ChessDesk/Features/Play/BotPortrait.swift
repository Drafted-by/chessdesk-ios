import SwiftUI

/// Where the art of the bots lives: the site serves it, the app shows it by
/// URL and never carries the files.
nonisolated enum PlayAssets {
    static let site = URL(string: "https://chessdesk.app").unsafelyUnwrapped

    /// A path on the site ("/bots/peru.webp") or a full URL.
    static func url(_ reference: String) -> URL? {
        if reference.hasPrefix("http://") || reference.hasPrefix("https://") { return URL(string: reference) }
        guard reference.hasPrefix("/") else { return nil }
        return URL(string: reference, relativeTo: site)?.absoluteURL
    }
}

/// A bot's portrait. Until the picture arrives, and when it cannot, the
/// frame holds the bot's initial: quiet, never a broken image.
struct BotPortrait: View {
    let avatar: String
    let name: String

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                CD.surface3
                Text(name.prefix(1))
                    .font(.custom("Newsreader72pt-Medium", fixedSize: max(12, side * 0.42)))
                    .foregroundStyle(CD.ink4)
                if let url = PlayAssets.url(avatar) {
                    AsyncImage(url: url, transaction: Transaction(animation: CD.Motion.enter)) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
    }
}

/// The flag of a bot's country, from its name. The site draws flags as SVG
/// files, which the system does not read; the system's own flags stand in.
/// A country the system does not know simply shows no flag.
nonisolated enum CountryFlag {
    /// Names the system writes otherwise ("China mainland", "United States").
    private static let aliases = ["USA": "US", "UK": "GB", "China": "CN", "Turkey": "TR", "Czech Republic": "CZ"]
    private static let england = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"

    private static let regionsByName: [String: String] = {
        let english = Locale(identifier: "en_US")
        var table: [String: String] = [:]
        for region in Locale.Region.isoRegions where region.identifier.count == 2 {
            if let name = english.localizedString(forRegionCode: region.identifier) { table[name] = region.identifier }
        }
        return table
    }()

    static func emoji(for country: String?) -> String? {
        guard let country else { return nil }
        if country == "England" { return england }
        guard let code = aliases[country] ?? regionsByName[country], code.count == 2 else { return nil }
        let scalars = code.unicodeScalars.compactMap { UnicodeScalar(0x1F1E6 + $0.value - 65) }
        return scalars.count == 2 ? String(String.UnicodeScalarView(scalars)) : nil
    }
}
