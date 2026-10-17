import Combine
import Contacts
import Foundation

/// One person ECHO can message or call. Built from the demo list or from the device address book.
struct ContactCard: Equatable {
    let name: String
    let phone: String?
    let email: String?
}

/// Looks people up by name. Demo contacts come first so the demo always works;
/// the device address book is only consulted when the user has already granted access.
@MainActor
final class ContactsDirectory: ObservableObject {
    private let store = CNContactStore()

    /// The safe sample contacts from DemoData.
    var allDemo: [ContactCard] {
        DemoData.contacts.map { ContactCard(name: $0.name, phone: $0.phone, email: $0.email) }
    }

    /// Who to reach in an emergency. Falls back to the first demo contact so there is always someone.
    var emergencyContact: ContactCard {
        if let contact = DemoData.emergencyContact {
            return ContactCard(name: contact.name, phone: contact.phone, email: contact.email)
        }
        return allDemo.first ?? ContactCard(name: "Emergency contact", phone: nil, email: nil)
    }

    /// Spoken list of the demo names, e.g. "Mom, Dr. Meyer and Neighbor Anna".
    var spokenDemoNames: String {
        let names = allDemo.map(\.name)
        guard names.count > 1, let last = names.last else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }

    /// Finds a contact by a spoken name. Case-insensitive, ignores punctuation, and accepts partial names
    /// ("anna" finds "Neighbor Anna"). Never prompts for Contacts permission.
    func find(_ name: String) -> ContactCard? {
        let query = Self.normalized(name)
        guard !query.isEmpty else { return nil }

        if let demo = allDemo.first(where: { card in
            let cardName = Self.normalized(card.name)
            return cardName.contains(query) || query.contains(cardName)
        }) {
            return demo
        }

        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return nil }
        return findOnDevice(name)
    }

    /// Asks for Contacts access if it has not been decided yet. Returns true when access is allowed.
    func requestDeviceAccess() async -> Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .authorized { return true }
        guard status == .notDetermined else { return false }
        return await withCheckedContinuation { continuation in
            store.requestAccess(for: .contacts) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Private

    private func findOnDevice(_ name: String) -> ContactCard? {
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]
        let predicate = CNContact.predicateForContacts(matchingName: name)
        guard let match = try? store.unifiedContacts(matching: predicate, keysToFetch: keys).first else {
            return nil
        }
        let fullName = [match.givenName, match.familyName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return ContactCard(
            name: fullName.isEmpty ? name : fullName,
            phone: match.phoneNumbers.first?.value.stringValue,
            email: match.emailAddresses.first.map { String($0.value) }
        )
    }

    /// Lowercase letters, digits and single spaces only.
    static func normalized(_ text: String) -> String {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: " ")
    }
}
