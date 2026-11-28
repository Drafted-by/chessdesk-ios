# The app icon

The icon is drawn in code, in the vocabulary of the engraved emblems
(`ChessDesk/UI/Emblems.swift`): an ink subject that breaks out of a board fragment, the dark
squares hatched at 45°, lit from the top left, exactly one brass element. It is redrawn at
icon scale (few strokes, a coarse hatch) rather than enlarged from the 32 grid.

## Render

```bash
design/icon/render.sh
```

This compiles `render.swift` with the app's own `ChessDesk/UI/SVGPath.swift` and writes, for
each candidate, into this folder:

| File | What it is |
|---|---|
| `<name>.png` | The icon, 1024 × 1024, opaque, square (iOS masks it) |
| `<name>-dark.png` | The iOS 18 dark appearance: the subject on a transparent ground |
| `<name>-tinted.png` | The iOS 18 tinted appearance: grayscale, opaque |
| `<name>-sheet.png` | Masked at 180, 120, 80 and 58 px on a dark and on a light wallpaper |
| `<name>-appearances-sheet.png` | The dark and tinted appearances at the same sizes |

## Candidates

- `knight` (installed): the knight of the puzzles emblem in front of a 2 × 2 board laid out
  like the mark of the logo, the lit square in brass.
- `mark`: the mark of the logo as an engraved board: one square brass, one paper, two hatched.
- `cameo`: a king in an oval frame, the frame in brass, the ground hatched.

## Install a candidate

```bash
icons=ChessDesk/Resources/Assets.xcassets/AppIcon.appiconset
cp design/icon/knight.png "$icons/AppIcon.png"
cp design/icon/knight-dark.png "$icons/AppIcon-Dark.png"
cp design/icon/knight-tinted.png "$icons/AppIcon-Tinted.png"
```

`Contents.json` names the three files; the dark and tinted ones carry
`"appearances": [{"appearance": "luminosity", "value": "dark" | "tinted"}]`.

## Round 2: ten candidates

JD asked for ten more ambitious tests. They are drawn in `round2.swift`, at icon scale, with
the material of the app's brass button (lighter at the top, an edge of light, a dark foot, a
short shade) and redrawn Staunton pieces on a 100 grid.

```bash
design/icon/render.sh round2
```

writes into `design/icon/round2/`:

| File | What it is |
|---|---|
| `overview.png` | The ten, masked and numbered, at 180 px on a dark and on a light wallpaper |
| `overview-small.png` | The same at 60 px, the size of the home screen |
| `<nn>-<name>.png` | The icon, 1024 × 1024, opaque, square |
| `<nn>-<name>-sheet.png` | Masked at 180, 120, 80 and 58 px on a dark and on a light wallpaper |

| No. | Name | Idea |
|---|---|---|
| 1 | `brass-knight` | The knight embossed in brass, the board pressed into the graphite |
| 2 | `engraved-knight` | A full-bleed head modelled only by engraving lines, the eye in brass |
| 3 | `inlaid-mark` | The mark of the logo as inlays: brass, paper, two engraved recesses |
| 4 | `monogram` | "cd" in Newsreader over the rule and its brass lozenge |
| 5 | `king-cameo` | A king in a brass-ringed medallion |
| 6 | `paper-knight` | The palette inverted: a page, the knight in dark ink, its square in brass |
| 7 | `board-crop` | Two squares across, bleeding off the edges, a paper rook cut by the frame |
| 8 | `better-move` | A brass arrow from a bishop to its square on an engraved board |
| 9 | `seal` | A struck brass coin bearing the knight |
| 10 | `promotion` | The pawn that earns its brass crown |

Round 2 renders the standard appearance only. The dark and tinted appearances of iOS 18 are
to be drawn for the candidate that is chosen, before it is installed.
