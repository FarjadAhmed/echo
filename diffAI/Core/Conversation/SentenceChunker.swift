import Foundation

/// Splits streamed text into sentences so speech can start before the answer is finished.
struct SentenceChunker {
    private var buffer = ""

    /// Common abbreviations whose period does not end a sentence.
    private static let abbreviations: Set<String> = ["dr", "mr", "mrs", "ms", "st", "no", "vs", "etc", "e.g", "i.e", "a.m", "p.m", "am", "pm", "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec", "mon", "tue", "wed", "thu", "fri", "sat", "sun"]

    /// Adds a piece of streamed text and returns any sentences that are now complete.
    mutating func append(_ piece: String) -> [String] {
        buffer += piece
        var sentences: [String] = []
        while let end = boundary(in: buffer) {
            let sentence = String(buffer[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer = String(buffer[end...])
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
        }
        return sentences
    }

    /// Returns whatever is left when the stream ends.
    mutating func finish() -> [String] {
        let rest = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return rest.isEmpty ? [] : [rest]
    }

    /// Index just after the first sentence end: a line break, or . ! ? (optionally followed by a closing
    /// quote or bracket) and then whitespace. Periods after abbreviations and single digits do not count.
    private func boundary(in text: String) -> String.Index? {
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            var next = text.index(after: index)

            if character == "\n" {
                return next
            }
            guard character == "." || character == "!" || character == "?" else {
                index = next
                continue
            }
            // Skip a closing quote or bracket right after the mark.
            while next < text.endIndex, "\"'”’)]".contains(text[next]) {
                next = text.index(after: next)
            }
            guard next < text.endIndex, text[next].isWhitespace else {
                index = next
                continue
            }
            if character == "." && isAbbreviation(endingAt: index, in: text) {
                index = next
                continue
            }
            return next
        }
        return nil
    }

    private func isAbbreviation(endingAt periodIndex: String.Index, in text: String) -> Bool {
        var start = periodIndex
        while start > text.startIndex {
            let previous = text.index(before: start)
            let character = text[previous]
            if character.isWhitespace { break }
            start = previous
        }
        let word = text[start..<periodIndex].lowercased()
        if word.isEmpty { return false }
        if word.count == 1, word.first?.isNumber == true { return true }
        return Self.abbreviations.contains(word)
    }
}
