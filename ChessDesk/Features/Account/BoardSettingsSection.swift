import ChessCore
import SwiftUI

/// You › Board and sound: the site's board appearance and sound choices
/// (`apps/web/components/board-theme/board-appearance.tsx`), kept on this
/// device. Every board in the app follows them at once.
struct BoardSettingsSection: View {
    @Bindable private var preferences = BoardPreferences.shared

    /// After 1. e4 e5 2. Nf3 Nc6 3. Bb5: every piece kind on both sides.
    private static let sampleFEN = "r1bqkbnr/pppp1ppp/2n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3"

    var body: some View {
        VStack(alignment: .leading, spacing: CD.Space.s12) {
            SectionHeader(title: "Board and sound", detail: "Kept on this device. Every board in the app follows it.")
            CDCard {
                VStack(alignment: .leading, spacing: CD.Space.s20) {
                    StaticBoardView(fen: Self.sampleFEN, highlight: (Square("f1")!, Square("b5")!))
                        .frame(maxWidth: 220)
                        .frame(maxWidth: .infinity)
                    group("Pieces") { pieces }
                    group("Board") { textures }
                    group("Squares") { colors }
                    if !preferences.theme.isStandard {
                        Button("Back to the standard board") { preferences.resetTheme() }
                            .buttonStyle(.cd(.ghost))
                    }
                    CDHairline()
                    sound
                    Text("Pieces: Kaneo and Kaneo Midnight by Kadagaden, and Kiwen Suwi by neverRare (its clip path removed so iOS draws it), CC BY 4.0; Fantasy and Spatial by Maurizio Monge, MIT licence; Chessnut by Alexis Luengas, Apache 2.0. Fabric texture from ambientCG, CC0.")
                        .cdFont(.meta)
                        .foregroundStyle(CD.ink4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: CD.Space.s8) {
            Text(title)
                .cdFont(.meta)
                .foregroundStyle(CD.ink3)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    // MARK: Choices

    private var pieces: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CD.Space.s8) {
                ForEach(PieceSet.allCases) { set in
                    tile(set.label, selected: preferences.pieceSet == set) {
                        preferences.pieceSet = set
                    } preview: {
                        Image(set.assetName(set.previewPiece))
                            .resizable()
                            .frame(width: 40, height: 40)
                            .padding(CD.Space.s4)
                            .background(preferences.lightSquare, in: RoundedRectangle(cornerRadius: CD.Radius.xs))
                    }
                }
            }
        }
        .scrollClipDisabled()
    }

    private var textures: some View {
        HStack(spacing: CD.Space.s8) {
            ForEach(BoardTexture.allCases) { texture in
                tile(texture.label, selected: preferences.texture == texture) {
                    preferences.texture = texture
                } preview: {
                    SquaresSample(texture: texture)
                        .frame(width: 48, height: 48)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var colors: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: CD.Space.s8)], spacing: CD.Space.s8) {
            ForEach(SquareColors.allCases) { scheme in
                tile(scheme.label, selected: preferences.squareColors == scheme) {
                    preferences.squareColors = scheme
                } preview: {
                    HStack(spacing: 0) {
                        HexColor.color(scheme.lightSquare)
                        HexColor.color(scheme.darkSquare)
                    }
                    .frame(width: 48, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: CD.Radius.xs))
                }
            }
        }
    }

    private func tile(
        _ label: String,
        selected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder preview: () -> some View
    ) -> some View {
        Button(action: action) {
            VStack(spacing: CD.Space.s6) {
                preview()
                Text(label)
                    .cdFont(.meta)
                    .foregroundStyle(selected ? CD.ink : CD.ink3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, CD.Space.s8)
            .padding(.vertical, CD.Space.s8)
            .frame(minWidth: 64, minHeight: 44)
            .background(selected ? CD.surface3 : CD.surface2, in: RoundedRectangle(cornerRadius: CD.Radius.md, style: .continuous))
            .hairline(selected ? CD.accentLine : CD.line, radius: CD.Radius.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(CDPressStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Sound

    private var sound: some View {
        VStack(alignment: .leading, spacing: CD.Space.s12) {
            Toggle(isOn: $preferences.sound.enabled) {
                Text("Move sounds")
                    .cdFont(.body)
                    .foregroundStyle(CD.ink)
            }
            .tint(CD.accent)
            .frame(minHeight: 44)
            HStack(spacing: CD.Space.s12) {
                Text("Volume")
                    .cdFont(.body)
                    .foregroundStyle(CD.ink)
                Slider(value: $preferences.sound.volume, in: 0...1, step: 0.05) { editing in
                    if !editing { BoardSounds.shared.play(capture: false) }
                }
                .tint(CD.accent)
                .accessibilityLabel("Volume")
                Text("\(Int((preferences.sound.volume * 100).rounded()))%")
                    .cdFont(.meta)
                    .foregroundStyle(CD.ink3)
                    .cdNumber()
                    .frame(width: 40, alignment: .trailing)
            }
            .frame(minHeight: 44)
            .opacity(preferences.sound.enabled ? 1 : 0.45)
            .disabled(!preferences.sound.enabled)
            Button("Play a sample") { BoardSounds.shared.play(capture: true) }
                .buttonStyle(.cd(.secondary, size: .small))
                .disabled(!preferences.sound.enabled)
        }
    }
}

/// A 2×2 corner of a board with a given texture and the current squares.
private struct SquaresSample: View {
    let texture: BoardTexture

    var body: some View {
        let preferences = BoardPreferences.shared
        ZStack {
            if let name = texture.imageName, texture != .fabric {
                Image(name).resizable()
            }
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    preferences.lightSquare
                    preferences.darkSquare
                }
                GridRow {
                    preferences.darkSquare
                    preferences.lightSquare
                }
            }
            .blendMode(texture == .linen || texture == .wood ? .multiply : .normal)
            if texture == .fabric, let name = texture.imageName {
                Image(name).resizable().blendMode(.softLight).opacity(0.45)
            }
        }
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: CD.Radius.xs))
        .accessibilityHidden(true)
    }
}

#Preview {
    ScrollView {
        BoardSettingsSection()
            .padding()
    }
    .background(CD.canvas)
}
