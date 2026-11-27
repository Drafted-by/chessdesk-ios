# chessdesk-ios

The native iOS app of [ChessDesk](https://chessdesk.app), for players, on iPhone and iPad.

SwiftUI, iOS 17 and later, English only. It is a native app, not a web view: the screens,
the board and the trainer are written in Swift. Everything a player owns (account, courses,
progress, Premium) lives on the ChessDesk backend, behind the app API (`/api/v1`) that the
site serves, so a change on the site reaches the app without a new build wherever the data
decides the result.

## What works today

- **Reach 1000 Elo**, put forward on Today and above the catalogue: the course page with its
  themes and stages, and each stage as a run of exercises (a lesson played with its
  explanations, or a position to solve). Two stages are free, without an account.
- **Stockfish 19 on the device**: while solving, a move that is not the course's is checked
  by the engine and accepted when it is as good (within 35 centipawns, or a mate on schedule),
  as on the site.
- **Opening courses**: the catalogue, a course page with its chapters and lines, open to guests.
- **The opening trainer**: learn a line move by move (notes, arrows, narration when the course
  is voiced), then play it from memory with hints. A guest can learn the free line of every course.
- **Guest first**: no account needed; what a guest learns is kept on the device and moves to
  their account when they sign in.
- **Sign in** with a ChessDesk email and password; Premium accounts get every line and their reviews.

Not built yet: buying Premium in the app (StoreKit), Sign in with Apple and Google, account
creation, own repertoires, games and their review with the engine, the eval bar, mistakes,
puzzles, bots, notifications, the "Learn chess" path. The Premium sheet says so.

## Run it

```bash
brew install xcodegen
scripts/fetch-nnue.sh          # once: the Stockfish network (98 MB, not committed)
scripts/sim.sh iphone          # build, install and launch on the "ChessDesk iPhone" simulator
scripts/sim.sh ipad
open ChessDesk.xcodeproj       # after `xcodegen generate`; the project file is not committed
```

The two simulators are created once:

```bash
xcrun simctl create "ChessDesk iPhone" com.apple.CoreSimulator.SimDeviceType.iPhone-17 com.apple.CoreSimulator.SimRuntime.iOS-27-0
xcrun simctl create "ChessDesk iPad" com.apple.CoreSimulator.SimDeviceType.iPad-Air-11-inch-M4 com.apple.CoreSimulator.SimRuntime.iOS-27-0
```

### Which backend

| Build | Backend |
|---|---|
| Release | `https://chessdesk.app` (`CDAPIBaseURL` in Info.plist) |
| Debug, default | **Sample data**: real answers captured from the site's dev server, in `Fixtures/api-v1` (a guest's view; three courses have their detail, Reach 1000 Elo has its two free stages) |
| Debug, `-CDBackend local` | `http://localhost:3000`, a site dev server forwarded from a Codespace (`gh codespace ports forward 3000:3000 -c <name>`) |
| Debug, `-CDBackend production` | `https://chessdesk.app` |

The choice is also in the app, tab You, section Developer (Debug builds only). Debug defaults
to sample data because the app API is merged on the site but not released yet.

Debug launch arguments open a screen directly, which is how screens are checked in the simulator:

```bash
scripts/sim.sh iphone -CDRoute course/practical-caro-kann
scripts/sim.sh iphone -CDRoute trainer/practical-caro-kann -CDTrainerSteps 5
scripts/sim.sh iphone -CDRoute trainer/practical-caro-kann -CDTrainerMemory YES
scripts/sim.sh iphone -CDRoute path
scripts/sim.sh iphone -CDRoute stage/back-rank-mate -CDExercise 3
```

## Tests

```bash
swift test --package-path Packages/ChessCore     # chess rules, no simulator needed
swift test --package-path Packages/StockfishEngine   # the engine, on the Mac
xcodebuild test -project ChessDesk.xcodeproj -scheme ChessDesk \
  -destination 'platform=iOS Simulator,name=ChessDesk iPhone'
```

What they hold:

- **ChessCore**: perft node counts on six reference positions (castling, en passant, promotion,
  pins), FEN, SAN.
- **Server lines replay**: every move of the captured sessions is legal for ChessCore, and the
  app and the server agree on the position and on the notation.
- **Narration**: the app computes the same clip key as the site for every note.
- **Contract**: an example built from the required fields of each schema in
  `contracts/openapi-v1.json` decodes into the app's models; every route the app calls is in the contract.
- **Trainer**: guided pass, wrong move held and taken back, memory pass grades, review grades,
  lessons, positions to solve, and when the engine is asked about another move.
- **Engine**: Stockfish finds a mate and judges material, on the Mac and inside the app in
  the simulator; the judge's two rules on a table of scores.

## Layout

```
ChessDesk/
├── ChessDeskApp.swift        @main, UIKit chrome
├── Core/
│   ├── API/                  ChessDeskAPI protocol, LiveAPI, FixtureAPI, models
│   ├── Session/              AppModel (account, backend), Keychain token, guest progress
│   └── Audio/                board sounds, narration
├── Features/                 Root, Today, Courses, Trainer, Account
├── UI/                       Tokens, Typography, Components, Board/
└── Resources/                Assets (pieces, board texture, icon), Fonts, Sounds
Packages/ChessCore/           chess rules in Swift: legal moves, FEN, SAN (no dependency)
Packages/StockfishEngine/     Stockfish 19 as a library: the official source (unmodified,
                              without main.cpp), an in-process UCI bridge, a Swift client
Fixtures/api-v1/              captured API answers (sample data, previews, tests)
contracts/openapi-v1.json     copy of the site's API contract (scripts/sync-contract.sh)
Tests/ChessDeskTests/
```

## Rules of the house

- **Design.** The site's design system is the reference (`apps/web/docs/design.md` in the
  `chessdesk` repository): warm graphite, paper ink, one brass accent, Newsreader for titles
  and prose, Geist for the rest. Colours, type and spacing come from `UI/Tokens.swift` and
  `UI/Typography.swift`, which mirror the site's tokens; a view never hardcodes them.
  One brass action per screen.
- **Backend first.** A rule that decides what a player may do or see (paywall, limits,
  scheduling) is the server's. The app shows what the API says; it does not recompute it.
- **The API is additive.** The app ignores unknown fields. When the site's API changes, run
  `scripts/sync-contract.sh`, then the tests.
- **Screens depend on `ChessDeskAPI`**, never on URLSession, so every screen runs on sample data.
- **A section appears in the tab bar when it works end to end.** No "coming soon" tabs.

## Credits and licences

- Chess pieces: CBurnett set by Colin M.L. Burnett, used under the BSD licence.
- Typefaces: Newsreader (Production Type) and Geist (Vercel), SIL Open Font License 1.1;
  licence texts in `ChessDesk/Resources/Fonts`.
- Board sounds: the two files of the site, from Lichess, under the licence obtained by
  Drafted-by, which covers the iOS app (confirmed by JD, 2026-11-27).
- Board texture: the owner's own asset.

## Licence

ChessDesk for iOS is free software under the **GNU General Public License, version 3**
(`LICENSE`), like the front-end of the site. It embeds [Stockfish](https://stockfishchess.org)
19, GPL-3.0, whose source is in `Packages/StockfishEngine/Sources/CStockfish/stockfish` with
its `Copying.txt` and `AUTHORS`. The engine is linked into the app and driven over UCI text
through `bridge.cpp`.

What the GPL asks of a release: whoever receives the app must be able to get this source.
The app's About section names the licence and links to this repository, so **the repository
has to be public (or the source offered another way) before a build is distributed**,
TestFlight included. The ChessDesk backend is not part of the app and stays proprietary.
