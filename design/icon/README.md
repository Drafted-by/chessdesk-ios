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
