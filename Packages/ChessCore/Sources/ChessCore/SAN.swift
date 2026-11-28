extension Position {
    /// Standard algebraic notation for a legal move, with "+" or "#".
    public func san(for move: Move) -> String? {
        let move = normalized(move)
        guard isLegal(move), let piece = self[move.from] else { return nil }
        var text = sanBody(for: move, piece: piece)
        if let next = playing(move) {
            if next.isCheckmate { text += "#" } else if next.isCheck { text += "+" }
        }
        return text
    }

    private func sanBody(for move: Move, piece: Piece) -> String {
        if isCastling(move) { return move.to.file == 6 ? "O-O" : "O-O-O" }
        let capture = isCapture(move)
        var text = piece.kind.sanLetter

        if piece.kind == .pawn {
            if capture { text += String(move.from.description.prefix(1)) }
        } else {
            let rivals = legalMoves().filter {
                $0.to == move.to && $0.from != move.from && self[$0.from] == piece
            }
            if !rivals.isEmpty {
                let sameFile = rivals.contains { $0.from.file == move.from.file }
                let sameRank = rivals.contains { $0.from.rank == move.from.rank }
                if !sameFile {
                    text += String(move.from.description.prefix(1))
                } else if !sameRank {
                    text += String(move.from.description.suffix(1))
                } else {
                    text += move.from.description
                }
            }
        }

        if capture { text += "x" }
        text += move.to.description
        if let promotion = move.promotion { text += "=" + promotion.sanLetter }
        return text
    }

    /// Finds the legal move a SAN string names. Check marks and annotation
    /// glyphs are ignored; "0-0" is accepted for castling.
    public func move(san: String) -> Move? {
        let wanted = Self.bareSAN(san)
        let castles = wanted.hasPrefix("O-O")
        return legalMoves().first { move in
            // Only the moves to the square the SAN names need their SAN written.
            guard castles ? isCastling(move) : wanted.contains(move.to.description),
                  let piece = self[move.from]
            else { return false }
            return sanBody(for: move, piece: piece) == wanted
        }
    }

    private static func bareSAN(_ san: String) -> String {
        san.replacingOccurrences(of: "0", with: "O")
            .filter { !"+#!?".contains($0) }
    }
}

extension String {
    fileprivate func replacingOccurrences(of target: Character, with replacement: Character) -> String {
        String(map { $0 == target ? replacement : $0 })
    }
}
