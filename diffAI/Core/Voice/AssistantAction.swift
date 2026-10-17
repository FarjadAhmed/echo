import Foundation

/// Everything the assistant can do for the user. Voice commands and live-AI tool calls both map to these.
/// Actions with consequences go through an ApprovalRequest first; see ActionExecutor.approvalRequest(for:).
enum AssistantAction: Equatable {
    case openScreen(AppScreen)
    case describeScene
    case takePhoto
    case readText
    case scanDocument
    case identifyColor
    case findObject(String)
    case openWebsite(String)
    case describeWebPage
    case readWebPage
    case clickElement(String)
    case typeInField(target: String, value: String)
    case scrollPage(down: Bool)
    case submitForm
    case readLink(Int)
    case nextHeading
    /// Recipient name and message, each nil when the user has not said it yet (ECHO asks).
    case composeEmail(to: String?, message: String? = nil)
    case composeText(to: String?, message: String? = nil)
    case readMessages
    case setReminder(String)
    /// Contact name, or empty to ask.
    case callContact(String)
    case whereAmI
    case emergency
    /// Calls the local emergency number (112, 911, 999 or 000), not a contact.
    case callEmergencyServices
    case dailyBriefing
    case sendCheckIn
    case switchInterface(InterfaceMode)
    case resetDemoData

    /// Actions with side effects are approved by the user before they run.
    var needsApproval: Bool {
        switch self {
        case .submitForm, .emergency, .callEmergencyServices, .sendCheckIn:
            return true
        case .callContact(let name):
            return !name.isEmpty
        default:
            return false
        }
    }
}
