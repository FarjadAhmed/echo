import UIKit

/// Bundled sample photos drawn in code, so the camera flow can be tried on the Simulator.
/// Each has a fixed description, and the medicine box contains real text for OCR.
struct SamplePhoto: Identifiable {
    let id: String
    let name: String
    let image: UIImage
    let description: String
}

enum SamplePhotos {
    static let all: [SamplePhoto] = [livingRoom, medicineBox, streetCrossing]

    static let livingRoom = SamplePhoto(
        id: "living-room",
        name: "Living room",
        image: render { context, size in
            fill(context, CGRect(origin: .zero, size: size), UIColor(red: 0.92, green: 0.88, blue: 0.80, alpha: 1))
            fill(context, CGRect(x: 0, y: size.height * 0.7, width: size.width, height: size.height * 0.3), UIColor(red: 0.59, green: 0.43, blue: 0.31, alpha: 1))
            fill(context, CGRect(x: 120, y: 420, width: 600, height: 220), UIColor(red: 0.24, green: 0.35, blue: 0.55, alpha: 1))
            fill(context, CGRect(x: 820, y: 120, width: 280, height: 300), UIColor(red: 0.67, green: 0.82, blue: 0.94, alpha: 1))
        },
        description: "A living room with a blue sofa on the left, a large window on the right, and a wooden floor. It looks calm and well lit."
    )

    static let medicineBox = SamplePhoto(
        id: "medicine-box",
        name: "Medicine box",
        image: render { context, size in
            fill(context, CGRect(origin: .zero, size: size), UIColor(white: 0.97, alpha: 1))
            fill(context, CGRect(x: 180, y: 90, width: 840, height: 720), UIColor(red: 0.0, green: 0.43, blue: 0.75, alpha: 1))
            drawText("PAIN RELIEF TABLETS", in: CGRect(x: 230, y: 160, width: 740, height: 120), size: 64)
            drawText("Take 1 tablet every 6 hours.", in: CGRect(x: 230, y: 340, width: 740, height: 100), size: 46)
            drawText("Do not take more than 4 in 24 hours.", in: CGRect(x: 230, y: 460, width: 740, height: 160), size: 46)
        },
        description: "A blue medicine box with white text. The label says pain relief tablets, take one tablet every six hours, and do not take more than four in twenty-four hours."
    )

    static let streetCrossing = SamplePhoto(
        id: "street-crossing",
        name: "Street crossing",
        image: render { context, size in
            fill(context, CGRect(origin: .zero, size: size), UIColor(red: 0.59, green: 0.78, blue: 0.94, alpha: 1))
            fill(context, CGRect(x: 0, y: size.height * 0.55, width: size.width, height: size.height * 0.45), UIColor(white: 0.24, alpha: 1))
            for stripe in 0..<8 {
                fill(context, CGRect(x: 180 + CGFloat(stripe) * 90, y: 560, width: 45, height: 260), UIColor.white)
            }
            fill(context, CGRect(x: 1000, y: 160, width: 70, height: 230), UIColor.black)
            context.setFillColor(UIColor.red.cgColor)
            context.fillEllipse(in: CGRect(x: 1015, y: 180, width: 40, height: 40))
        },
        description: "A street crossing with white stripes across the road. A traffic light on the right is showing red. Wait until it shows green and the way is clear."
    )

    private static func render(_ draw: (CGContext, CGSize) -> Void) -> UIImage {
        let size = CGSize(width: 1200, height: 900)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            draw(renderer.cgContext, size)
        }
    }

    private static func fill(_ context: CGContext, _ rect: CGRect, _ color: UIColor) {
        context.setFillColor(color.cgColor)
        context.fill(rect)
    }

    private static func drawText(_ text: String, in rect: CGRect, size: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: size),
            .foregroundColor: UIColor.white,
        ]
        NSString(string: text).draw(in: rect, withAttributes: attributes)
    }
}
