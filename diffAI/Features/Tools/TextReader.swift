import UIKit
import Vision

/// On-device text recognition with Vision. Works offline, and never sends the photo anywhere.
enum TextReader {
    /// Returns the text found in the photo, one line after another. Empty when there is none.
    static func read(_ image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        let orientation = Self.orientation(of: image)

        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            do {
                try handler.perform([request])
            } catch {
                return ""
            }
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return TextReader.spoken(lines)
        }.value
    }

    /// Joins recognised lines into speakable text. A line that wraps mid-sentence ("not more than 4 in 24" /
    /// "hours.") continues without a pause; a line followed by a new sentence ends with a period.
    nonisolated static func spoken(_ lines: [String]) -> String {
        var result = ""
        for (index, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            result += line
            guard index < lines.count - 1 else { break }
            let endsSentence = line.last.map { ".!?:;".contains($0) } ?? false
            let nextStartsUpper = lines[index + 1].trimmingCharacters(in: .whitespaces).first?.isUppercase ?? false
            result += (!endsSentence && nextStartsUpper) ? ". " : " "
        }
        let trimmed = result.trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.last else { return trimmed }
        return ".!?".contains(last) ? trimmed : trimmed + "."
    }

    /// Maps the UIKit orientation of a photo to the one Vision expects.
    private static func orientation(of image: UIImage) -> CGImagePropertyOrientation {
        switch image.imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
