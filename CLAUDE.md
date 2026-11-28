# Working in this repository

ChessDesk for iOS: the native app of chessdesk.app. SwiftUI, Swift 6, iOS 17+. Read `README.md` first.

## Build and test

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate            # after adding, moving or removing a file (the .xcodeproj is not committed)
xcodebuild test -project ChessDesk.xcodeproj -scheme ChessDesk \
  -destination "platform=iOS Simulator,name=<your simulator>" -derivedDataPath .build/DerivedData
scripts/sim.sh iphone -CDRoute <route>    # build, install, launch on "ChessDesk iPhone"
```

A fresh worktree has neither the Stockfish network nor the board sounds (both untracked). Copy them from the main checkout instead of downloading 98 MB:

```bash
cp -c ~/repos/chessdesk-ios/ChessDesk/Resources/Engine/*.nnue ChessDesk/Resources/Engine/
cp -c ~/repos/chessdesk-ios/ChessDesk/Resources/Sounds/*.mp3 ChessDesk/Resources/Sounds/ 2>/dev/null || true
```

Several agents may build at once on this Mac. Use the simulator named in your task, never another agent's, and your own `.build/` inside your worktree.

## Architecture

- `ChessDesk/Core/API`: `ChessDeskAPI` is the protocol every screen talks to; `LiveAPI` is the HTTP client, `FixtureAPI` the offline one. `contracts/openapi-v1.json` mirrors the site's contract (`apps/web/docs/api/openapi-v1.json` in `Drafted-by/chessdesk`); `ContractTests` checks the models against it.
- `ChessDesk/Core/Session/AppModel.swift`: who is signed in, the token, the client. Views read it from the environment.
- `ChessDesk/Core/Review`, `Core/Engine`, `Packages/StockfishEngine`: Stockfish on the device. One engine per process, one search at a time.
- `Packages/ChessCore`: the rules of chess (positions, legal moves, SAN). No UI, no I/O.
- `ChessDesk/Features/<Feature>/`: one folder per feature. `ChessDesk/UI`: the kit (tokens, typography, components, board).
- App code is on the main actor by default (`SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor`). Value types, shapes and anything used off the main actor say `nonisolated`.

### Adding a feature without colliding with other work

Other branches are adding features at the same time. Keep shared files almost untouched:

- API models of a feature go in `ChessDesk/Core/API/Models+<Feature>.swift`; its client calls in `ChessDesk/Core/API/API+<Feature>.swift` as a protocol `<Feature>API` plus `extension LiveAPI: <Feature>API` and `extension FixtureAPI: <Feature>API`. Then add the protocol to the inheritance list of `ChessDeskAPI` (one line) so `app.api` offers it.
- A new screen is reached by one line in `RootView.swift` or from an existing hub screen. Do not restructure the tab bar on your own: say in your report where the feature should hang.
- Do not reformat or reorder code you are not changing.

## Product rules

- **The server decides.** Entitlements, limits, grading and spacing rules live on the site. The app shows what the API answers; it never unlocks Premium or computes a limit on its own. The one exception is chess itself: the engine and the rules run on the device.
- **Same results as the site.** When the site computes something in the browser (a game review, a bot's move, a puzzle's grading), port its arithmetic and its thresholds, and port its tests' expectations. Name the site file you ported from in a comment.
- **Guest first.** What can work without an account does. A feature that needs one says so on its own screen, with Create an account and Sign in.
- **No "coming soon".** A screen appears when it works end to end.

## Design

The design system is the site's `apps/web/docs/design.md`. In short: warm graphite surfaces, one brass accent, Newsreader for titles and prose, Geist for interface text. Use the tokens (`CD.*`), `cdFont(...)`, and the components of `ChessDesk/UI/Components.swift`; never a raw colour or font in a screen.

- Ornaments (`.plate()`, `OrnamentRule`, `Emblem`, the `.lead` button) are for brand moments: the one plate of a screen, the thing being sold. Never on a working screen (a trainer, a board, a list, a form of settings).
- One `primary` button per view. Sentence case everywhere. English only, plain words.
- Semantic colours carry meaning only: `CD.win`, `CD.loss`, `CD.caution`, `CD.danger`.
- Every tappable thing is at least 44 pt. VoiceOver labels on icon buttons. Respect Reduce Motion.
- No invented social proof, no fake numbers, no placeholder content shipped.

## Tests

Swift Testing. Every feature comes with tests of its logic (models decode from the contract's examples, rules ported from the site give the site's results, the model of a screen goes through its states with a stub API). Stubs implement only what they exercise: `Tests/ChessDeskTests/ReviewTests.swift` holds default implementations for the rest; add yours next to them.

`PremiumStoreTests` needs a signed app and is skipped on CI; it has failed once in parallel runs on a Mac and passed on rerun.

## Git

Work on the branch of your worktree. Small commits, a subject that says what changed for the player, a body that says why. Do not push to `main` and do not merge: the pilot integrates branches. Never commit the Stockfish network, the sounds, a key or a provisioning profile.
