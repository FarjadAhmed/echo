import Foundation

/// Fake, safe sample content for the demo. Nothing here is real personal data.
enum DemoData {
    struct Contact: Identifiable {
        let id = UUID()
        let name: String
        let phone: String
        let email: String
        let isEmergency: Bool
    }

    static let contacts: [Contact] = [
        Contact(name: "Mom", phone: "+15555550101", email: "mom@example.com", isEmergency: true),
        Contact(name: "Dr. Meyer", phone: "+15555550102", email: "office@example.com", isEmergency: false),
        Contact(name: "Neighbor Anna", phone: "+15555550103", email: "anna@example.com", isEmergency: false),
    ]

    static var emergencyContact: Contact? {
        contacts.first { $0.isEmergency }
    }

    struct InboxSeed {
        let kind: String
        let sender: String
        let subject: String
        let body: String
    }

    static let inbox: [InboxSeed] = [
        InboxSeed(kind: "email", sender: "Mom", subject: "Sunday lunch", body: "Are you still coming for lunch on Sunday? I am making soup."),
        InboxSeed(kind: "text", sender: "Dr. Meyer", subject: "", body: "Reminder: your check-up is on Thursday at ten in the morning."),
        InboxSeed(kind: "text", sender: "Neighbor Anna", subject: "", body: "I have your parcel. I will bring it over this evening."),
    ]

    struct ReminderSeed {
        let title: String
        let hour: Int
        let minute: Int
        let repeatsDaily: Bool
    }

    static let reminders: [ReminderSeed] = [
        ReminderSeed(title: "Take your pills", hour: 8, minute: 0, repeatsDaily: true),
        ReminderSeed(title: "Evening walk", hour: 18, minute: 30, repeatsDaily: false),
    ]

    struct CaregiverEntry {
        let time: String
        let event: String
    }

    static let caregiverActivity: [CaregiverEntry] = [
        CaregiverEntry(time: "8:02 AM", event: "Morning medication confirmed"),
        CaregiverEntry(time: "9:40 AM", event: "Read two messages"),
        CaregiverEntry(time: "11:15 AM", event: "Asked for the weather"),
        CaregiverEntry(time: "1:30 PM", event: "Took a photo to read a medicine label"),
    ]

    static let caregiverLastLocation = "Home, Maple Street (demo location)"
    static let caregiverAdherence = "Medication taken on 6 of the last 7 days (demo data)"

    static let weather = "mild, with light cloud and around 18 degrees"
}
