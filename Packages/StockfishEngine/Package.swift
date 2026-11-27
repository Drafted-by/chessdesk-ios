// swift-tools-version: 6.0
import PackageDescription

// Stockfish 19 (GPL-3.0), built as a library, with a small Swift client.
// The engine source in Sources/CStockfish/stockfish is the official release,
// unmodified except that main.cpp and the universal-binary files are left out.
let package = Package(
    name: "StockfishEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "StockfishEngine", targets: ["StockfishEngine"]),
    ],
    targets: [
        .target(
            name: "CStockfish",
            exclude: ["stockfish/Copying.txt", "stockfish/AUTHORS", "stockfish/incbin/UNLICENCE"],
            cxxSettings: [
                .headerSearchPath("stockfish"),
                .define("NDEBUG"),
                .define("IS_64BIT"),
                .define("USE_PTHREADS"),
                .define("USE_POPCNT"),
                .define("USE_NEON", to: "8"),
                // The network is a file of the app bundle, not part of the binary.
                .define("NNUE_EMBEDDING_OFF"),
                // An engine built without optimisation is some twenty times slower.
                // Warnings of the vendored engine are upstream's to fix, not ours.
                .unsafeFlags(["-O3", "-fno-exceptions", "-w"]),
            ]
        ),
        .target(name: "StockfishEngine", dependencies: ["CStockfish"]),
        .testTarget(name: "StockfishEngineTests", dependencies: ["StockfishEngine"]),
    ],
    cxxLanguageStandard: .cxx17
)
