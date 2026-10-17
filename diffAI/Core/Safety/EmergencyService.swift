import Combine
import Foundation
import UIKit

/// Emergency (SOS) flow: call the emergency contact, then offer to text caregivers with the user's location.
///
/// iOS cannot place calls or send texts silently from a third-party app. We can only open the Phone or
/// Messages app with the number and text filled in; the user confirms the call or taps Send in the
/// system UI. That is also the safety property we want: nothing contacts anyone without the user seeing it.
@MainActor
final class EmergencyService: ObservableObject {
    /// Set after a call was started. The orchestrator presents this as a second approval request;
    /// confirming it runs `runFollowUp()`, declining it runs `cancelFollowUp()`.
    @Published private(set) var pendingFollowUp: ApprovalRequest?

    private var contactName: String?
    private var locationText: String?
    private var followUpPhone: String?
    private var followUpBody: String?

    private var caregiverName: String {
        DemoData.emergencyContact?.name ?? "your caregiver"
    }

    private var caregiverPhone: String {
        DemoData.emergencyContact?.phone ?? ""
    }

    // MARK: - Step 1: the call

    /// Approval shown before anything happens. Remembers the name and location for the follow-up text.
    func approvalRequest(contactName: String, locationText: String?) -> ApprovalRequest {
        self.contactName = contactName
        self.locationText = locationText
        return ApprovalRequest(
            title: "Emergency",
            summary: "I will call \(contactName) now. After the call, I will offer to text your caregivers with your location.",
            rows: [
                ApprovalRequest.Row(label: "Calling", value: contactName),
                ApprovalRequest.Row(label: "Location", value: locationText ?? "not known yet"),
            ],
            caution: "This is for real emergencies. If you are in immediate danger, call your local emergency number.",
            confirmLabel: "Call now"
        )
    }

    /// Opens the Phone app with the number dialled. Returns the sentence to speak.
    /// On the Simulator (and iPads without a phone) `tel:` cannot be opened; we say so instead of crashing.
    func startCall(phone: String) -> String {
        let name = contactName ?? "your emergency contact"
        guard let url = Self.telURL(phone), UIApplication.shared.canOpenURL(url) else {
            return "Calls are not available on this device."
        }
        ExternalApp.open(url)
        prepareFollowUp()
        return "Calling \(name)."
    }

    // MARK: - Step 2: the follow-up text

    private func prepareFollowUp() {
        let location = locationText ?? DemoData.caregiverLastLocation
        let body = "I need help. My location is \(location)."
        followUpPhone = caregiverPhone
        followUpBody = body
        pendingFollowUp = ApprovalRequest(
            title: "Text your caregivers",
            summary: "I will open Messages with a text to \(caregiverName) saying: \(body) You tap Send there.",
            rows: [
                ApprovalRequest.Row(label: "To", value: caregiverName),
                ApprovalRequest.Row(label: "Message", value: body),
            ],
            confirmLabel: "Open Messages"
        )
    }

    /// Opens Messages with the caregiver text filled in. The user must tap Send.
    func runFollowUp() -> String {
        defer { cancelFollowUp() }
        guard let phone = followUpPhone, let body = followUpBody,
              let url = Self.smsURL(phone: phone, body: body),
              UIApplication.shared.canOpenURL(url) else {
            return "Texts are not available on this device."
        }
        ExternalApp.open(url)
        return "Messages is opening with your text to \(caregiverName). Tap Send there to send it."
    }

    func cancelFollowUp() {
        pendingFollowUp = nil
        followUpPhone = nil
        followUpBody = nil
    }

    // MARK: - URLs

    static func telURL(_ phone: String) -> URL? {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(digits)")
    }

    /// `sms:<number>&body=<text>`. The body is percent-encoded so punctuation survives.
    static func smsURL(phone: String, body: String) -> URL? {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let encoded = body.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "sms:\(digits)&body=\(encoded)")
    }
}
