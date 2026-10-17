import CoreGraphics
import UIKit

/// Names the main color of a photo by averaging its centre. A rough answer, and the reply says so.
enum ColorIdentifier {
    private static let palette: [(name: String, r: Double, g: Double, b: Double)] = [
        ("white", 0.95, 0.95, 0.95),
        ("black", 0.08, 0.08, 0.08),
        ("grey", 0.5, 0.5, 0.5),
        ("red", 0.8, 0.15, 0.15),
        ("orange", 0.95, 0.5, 0.12),
        ("yellow", 0.95, 0.85, 0.2),
        ("green", 0.2, 0.6, 0.25),
        ("blue", 0.15, 0.3, 0.8),
        ("purple", 0.5, 0.2, 0.6),
        ("pink", 0.95, 0.55, 0.7),
        ("brown", 0.45, 0.3, 0.15),
        ("beige", 0.86, 0.8, 0.65),
    ]

    static func describe(_ image: UIImage) -> String {
        guard let rgb = averageCenterColor(of: image),
              let name = nearestName(r: rgb.r, g: rgb.g, b: rgb.b) else {
            return "I could not read the colors in this photo."
        }
        return "The main color in the middle of the photo is \(name). This is a rough answer from the centre of the picture."
    }

    /// Shrinks the centre of the image to one pixel, which gives its average colour.
    private static func averageCenterColor(of image: UIImage) -> (r: Double, g: Double, b: Double)? {
        guard let cgImage = image.cgImage else { return nil }
        let crop = CGRect(
            x: CGFloat(cgImage.width) * 0.3,
            y: CGFloat(cgImage.height) * 0.3,
            width: CGFloat(cgImage.width) * 0.4,
            height: CGFloat(cgImage.height) * 0.4
        )
        guard let center = cgImage.cropping(to: crop) else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        var drawn = false
        pixel.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.interpolationQuality = .medium
            context.draw(center, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            drawn = true
        }
        guard drawn else { return nil }
        return (Double(pixel[0]) / 255, Double(pixel[1]) / 255, Double(pixel[2]) / 255)
    }

    private static func nearestName(r: Double, g: Double, b: Double) -> String? {
        palette.min { distance($0, r, g, b) < distance($1, r, g, b) }?.name
    }

    private static func distance(_ color: (name: String, r: Double, g: Double, b: Double), _ r: Double, _ g: Double, _ b: Double) -> Double {
        let dr = color.r - r
        let dg = color.g - g
        let db = color.b - b
        return dr * dr + dg * dg + db * db
    }
}
