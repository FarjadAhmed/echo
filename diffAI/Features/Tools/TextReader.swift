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
            return lines.joined(separator: ". ")
        }.value
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
