import ChessCore
import Foundation
import Observation
import SwiftUI

/// How every board in the app looks and sounds: the choices of You › Board
/// and sound. Stored on this device in the site's own shapes
/// (`apps/web/lib/board-theme/index.ts` and `lib/board-sound/settings.ts`);
/// signed in, `AccountSettingsModel` keeps them in step with the account's
/// settings (`board.theme` and `board.sound` of `GET /api/v1/settings`).
@Observable
final class BoardPreferences {
    /// The site's `BoardTheme`: field names and values as the site stores them.
    nonisolated struct Theme: Codable, Hashable, Sendable {
        var pieceSet: String
        var boardTexture: String
        var lightSquare: String
        var darkSquare: String

        /// Linen texture, Brown squares, CBurnett pieces (the site's default).
        static let standard = Theme(
            pieceSet: PieceSet.cburnett.rawValue,
            boardTexture: BoardTexture.linen.rawValue,
            lightSquare: SquareColors.brown.lightSquare,
            darkSquare: SquareColors.brown.darkSquare
        )

        /// Any stored value to a valid theme: an unknown set or texture, or a
        /// colour that is not a hex colour, takes the default (`normalizeBoardTheme`).
        func normalized() -> Theme {
            Theme(
                pieceSet: PieceSet(rawValue: pieceSet) == nil ? Self.standard.pieceSet : pieceSet,
                boardTexture: BoardTexture(rawValue: boardTexture) == nil ? Self.standard.boardTexture : boardTexture,
                lightSquare: HexColor.isValid(lightSquare) ? lightSquare : Self.standard.lightSquare,
                darkSquare: HexColor.isValid(darkSquare) ? darkSquare : Self.standard.darkSquare
            )
        }

        var isStandard: Bool {
            pieceSet == Self.standard.pieceSet && boardTexture == Self.standard.boardTexture
                && lightSquare.lowercased() == Self.standard.lightSquare && darkSquare.lowercased() == Self.standard.darkSquare
        }
    }

    /// The site's `BoardSoundSettings`.
    nonisolated struct Sound: Codable, Hashable, Sendable {
        var enabled: Bool
        /// 0…1.
        var volume: Double

        /// On, at a low volume (`DEFAULT_BOARD_SOUND`).
        static let standard = Sound(enabled: true, volume: 0.35)

        func normalized() -> Sound {
            Sound(enabled: enabled, volume: volume.isFinite ? min(1, max(0, volume)) : Self.standard.volume)
        }
    }

    /// The device's choices, read by every board and by the board sounds.
    /// Reading its properties in a view's body redraws the view on a change.
    static let shared = BoardPreferences()

    static let themeKey = "cd.board.theme"
    static let soundKey = "cd.board.sound"

    var theme: Theme {
        didSet { save(theme, as: Self.themeKey) }
    }

    var sound: Sound {
        didSet { save(sound, as: Self.soundKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = Self.load(Theme.self, from: defaults, key: Self.themeKey)?.normalized() ?? .standard
        sound = Self.load(Sound.self, from: defaults, key: Self.soundKey)?.normalized() ?? .standard
    }

    // MARK: What the board draws

    var pieceSet: PieceSet {
        get { PieceSet(rawValue: theme.pieceSet) ?? .cburnett }
        set { theme.pieceSet = newValue.rawValue }
    }

    var texture: BoardTexture {
        get { BoardTexture(rawValue: theme.boardTexture) ?? .linen }
        set { theme.boardTexture = newValue.rawValue }
    }

    /// The preset the two square colours match, if any.
    var squareColors: SquareColors? {
        get {
            SquareColors.allCases.first {
                $0.lightSquare == theme.lightSquare.lowercased() && $0.darkSquare == theme.darkSquare.lowercased()
            }
        }
        set {
            guard let newValue else { return }
            theme.lightSquare = newValue.lightSquare
            theme.darkSquare = newValue.darkSquare
        }
    }

    var lightSquare: Color { HexColor.color(theme.lightSquare) ?? CD.Board.light }
    var darkSquare: Color { HexColor.color(theme.darkSquare) ?? CD.Board.dark }

    /// Back to the site's default look. Sound is not part of the theme.
    func resetTheme() {
        theme = .standard
    }

    // MARK: Storage

    private func save(_ value: some Encodable, as key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func load<Value: Decodable>(_ type: Value.Type, from defaults: UserDefaults, key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

/// The piece sets of the site (`PIECE_SETS`), same values and labels.
nonisolated enum PieceSet: String, CaseIterable, Identifiable, Sendable {
    case cburnett
    case kaneo
    case kaneoMidnight = "kaneo-midnight"
    case fantasy
    case spatial
    case kiwenSuwi = "kiwen-suwi"
    case chessnut

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cburnett: "CBurnett"
        case .kaneo: "Kaneo"
        case .kaneoMidnight: "Kaneo Midnight"
        case .fantasy: "Fantasy"
        case .spatial: "Spatial"
        case .kiwenSuwi: "Kiwen Suwi"
        case .chessnut: "Chessnut"
        }
    }

    /// The piece the picker shows: the set's own knight (a black one for
    /// Kaneo Midnight, as on the site).
    var previewPiece: Piece { Piece(self == .kaneoMidnight ? .black : .white, .knight) }

    /// Asset name of one drawing: "piece-wN" for CBurnett, "piece-kaneo-wN".
    func assetName(_ piece: Piece) -> String {
        let code = "\(piece.side == .white ? "w" : "b")\(String(piece.kind.rawValue).uppercased())"
        return self == .cburnett ? "piece-\(code)" : "piece-\(rawValue)-\(code)"
    }
}

/// The textures under the squares (`BOARD_TEXTURES`).
nonisolated enum BoardTexture: String, CaseIterable, Identifiable, Sendable {
    case linen = "default"
    case plain
    case fabric = "canvas"
    case wood

    var id: String { rawValue }

    var label: String {
        switch self {
        case .linen: "Linen"
        case .plain: "Plain"
        case .fabric: "Fabric"
        case .wood: "Wood"
        }
    }

    var imageName: String? {
        switch self {
        case .linen: "board-linen"
        case .plain: nil
        case .fabric: "board-canvas"
        case .wood: "board-wood"
        }
    }
}

/// The square colour presets (`COLOR_SCHEMES`), lowercase hex as the site writes them.
nonisolated enum SquareColors: String, CaseIterable, Identifiable, Sendable {
    case brown, study, green, blue, grey, purple

    var id: String { rawValue }

    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    var lightSquare: String {
        switch self {
        case .brown: "#f0d9b5"
        case .study: "#bab5c5"
        case .green: "#eeeed2"
        case .blue: "#dee3e6"
        case .grey: "#dcdcdc"
        case .purple: "#e6dcf0"
        }
    }

    var darkSquare: String {
        switch self {
        case .brown: "#b58863"
        case .study: "#706f8a"
        case .green: "#769656"
        case .blue: "#8ca2ad"
        case .grey: "#909090"
        case .purple: "#9a7bc0"
        }
    }
}

/// CSS hex colours, 3 or 6 digits (`isHexColor`).
nonisolated enum HexColor {
    static func isValid(_ text: String) -> Bool {
        guard text.hasPrefix("#") else { return false }
        let digits = text.dropFirst()
        return (digits.count == 3 || digits.count == 6) && digits.allSatisfy(\.isHexDigit)
    }

    static func color(_ text: String) -> Color? {
        guard isValid(text) else { return nil }
        var digits = String(text.dropFirst())
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard let value = UInt32(digits, radix: 16) else { return nil }
        return Color(hex: value)
    }
}
