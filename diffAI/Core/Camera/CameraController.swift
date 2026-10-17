import Combine
import Foundation

/// What the user wants done with the next photo.
enum CapturePurpose: Equatable {
    case describe
    case readText
    case scanDocument
    case identifyColor
    case findObject(String)

    var prompt: String {
        switch self {
        case .describe: return "Describe this photo"
        case .readText: return "Read the text in this photo"
        case .scanDocument: return "Scan and summarize this document"
        case .identifyColor: return "What color is this?"
        case .findObject(let target): return "Where is \(target)?"
        }
    }

    var historyKind: String {
        switch self {
        case .describe: return "Description"
        case .readText: return "Text"
        case .scanDocument: return "Document"
        case .identifyColor: return "Color"
        case .findObject: return "Find"
        }
    }
}

/// Connects voice commands to the camera screen. A request made before the camera is ready waits here.
@MainActor
final class CameraController: ObservableObject {
    /// Quick mode picked on screen, used when the user taps the shutter.
    @Published var mode: CapturePurpose = .describe
    /// A voice request waiting for a photo.
    @Published private(set) var pendingPurpose: CapturePurpose?

    func request(_ purpose: CapturePurpose) {
        pendingPurpose = purpose
    }

    /// Returns the waiting request and clears it.
    func takePendingRequest() -> CapturePurpose? {
        let purpose = pendingPurpose
        pendingPurpose = nil
        return purpose
    }
}
