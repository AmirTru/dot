import Foundation
import Testing
@testable import WritingCore

@Test func piecesFoundInOrder() { #expect(pieceOffsets(["can yu ", "chek", " teh"], in: "can yu chek teh") == [0, 7, 11]) }
@Test func repeatedPieceUsesNextOccurrence() { #expect(pieceOffsets(["ab", "ab"], in: "ab ab") == [0, 3]) }
@Test func missingPieceIsNil() { #expect(pieceOffsets(["x", "chek"], in: "can chek") == [nil, 4]) }
@Test func emptyPieceIsNil() { #expect(pieceOffsets(["", "can"], in: "can") == [nil, 0]) }
@Test func locateInsidePiece() {
    let r = locate(NSRange(location: 7, length: 4), pieces: [NSRange(location: 0, length: 7), NSRange(location: 7, length: 4)])
    #expect(r?.index == 1 && r?.local == NSRange(location: 0, length: 4))
}
@Test func locateAcrossPiecesIsNil() { #expect(locate(NSRange(location: 5, length: 4), pieces: [NSRange(location: 0, length: 7), NSRange(location: 7, length: 4)]) == nil) }
