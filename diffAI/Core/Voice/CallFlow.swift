import Foundation

/// "Call" with no name: asks who, then hands back an approval request to place the call.
@MainActor
final class CallFlow: DialogFlow {
    private let lookup: (String) -> (name: String, phone: String)?
    private let place: (String, String) -> String
    private var attempts = 0

    /// lookup finds a contact by spoken name; place starts the call and returns the sentence to speak.
    init(lookup: @escaping (String) -> (name: String, phone: String)?, place: @escaping (String, String) -> String) {
        self.lookup = lookup
        self.place = place
    }

    func start() async -> DialogStep {
        .ask("Who do you want to call?")
    }

    func handle(_ reply: String) async -> DialogStep {
        guard let contact = lookup(reply) else {
            attempts += 1
            if attempts >= 2 {
                return .finish("I could not find that person. You can add them to your contacts and try again.")
            }
            return .ask("I could not find \(reply). I know Mom, Dr. Meyer and Neighbor Anna. Who should I call?")
        }
        let place = self.place
        let request = ApprovalRequest(
            title: "Call \(contact.name)",
            summary: "I will start a phone call to \(contact.name).",
            rows: [ApprovalRequest.Row(label: "Number", value: contact.phone)],
            confirmLabel: "Call now"
        )
        return .approve(request) { place(contact.name, contact.phone) }
    }
}
