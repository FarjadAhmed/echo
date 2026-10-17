import Foundation
import UIKit

/// A guided dialog to run for an action, plus the progress steps to show while it runs.
struct FlowRequest {
    let flow: any DialogFlow
    let steps: [String]
}

/// Carries out assistant actions and returns the sentence to speak back.
/// Feature modules are plugged in here; the engine never talks to them directly.
@MainActor
final class ActionExecutor {
    private let router: AppRouter
    private let settings: AppSettings
    private let camera: CameraController
    private let web: WebAssistantController
    private let contacts: ContactsDirectory
    private let compose: ComposeCoordinator
    private let inbox: InboxStore
    private let reminders: ReminderStore
    private let location: LocationService
    private let emergency: EmergencyService
    private let caregiver: CaregiverStore
    private let history: HistoryStore
    private let makeAIService: () -> any AIService

    init(
        router: AppRouter,
        settings: AppSettings,
        camera: CameraController,
        web: WebAssistantController,
        contacts: ContactsDirectory,
        compose: ComposeCoordinator,
        inbox: InboxStore,
        reminders: ReminderStore,
        location: LocationService,
        emergency: EmergencyService,
        caregiver: CaregiverStore,
        history: HistoryStore,
        makeAIService: @escaping () -> any AIService
    ) {
        self.router = router
        self.settings = settings
        self.camera = camera
        self.web = web
        self.contacts = contacts
        self.compose = compose
        self.inbox = inbox
        self.reminders = reminders
        self.location = location
        self.emergency = emergency
        self.caregiver = caregiver
        self.history = history
        self.makeAIService = makeAIService
    }

    var currentScreenName: String {
        router.currentScreenName
    }

    var lastWebSnapshot: WebPageSnapshot? {
        web.lastSnapshot
    }

    var readerStatus: ReaderStatus {
        web.readerStatus
    }

    var lastKnownLocation: String? {
        location.lastKnownDescription
    }

    /// After an emergency call, the offer to text caregivers with the location.
    var emergencyFollowUp: ApprovalRequest? {
        emergency.pendingFollowUp
    }

    func runEmergencyFollowUp() -> String {
        caregiver.log("Emergency text sent to caregivers")
        return emergency.runFollowUp()
    }

    func cancelEmergencyFollowUp() {
        emergency.cancelFollowUp()
    }

    func goHome() {
        router.goHome()
    }

    func goBack() {
        router.goBack()
    }

    func stopReading() {
        web.stopReading()
    }

    func pauseReading() {
        web.pauseReading()
    }

    func resumeReading() {
        web.resumeReading()
    }

    func skipChunk() {
        web.skipChunk()
    }

    /// Actions that need a back-and-forth with the user return a dialog instead of running at once.
    func flow(for action: AssistantAction) -> FlowRequest? {
        switch action {
        case .composeText(let name, let message):
            return composeFlow(.text, name: name, message: message, appName: "Messages")
        case .composeEmail(let name, let message):
            return composeFlow(.email, name: name, message: message, appName: "Mail")
        case .readMessages:
            return FlowRequest(
                flow: ReadInboxFlow(inbox: inbox, contacts: contacts, compose: compose, ai: makeAIService()),
                steps: []
            )
        case .setReminder(let text):
            return FlowRequest(
                flow: ReminderFlow(text: text, store: reminders),
                steps: ["Understand the time", "Save the reminder"]
            )
        case .callContact(let name) where name.isEmpty:
            let flow = CallFlow(
                lookup: { [contacts] spoken in
                    guard let card = contacts.find(spoken), let phone = card.phone else { return nil }
                    return (card.name, phone)
                },
                place: { [weak self] contactName, phone in
                    self?.placeCall(name: contactName, phone: phone) ?? "I could not start that call."
                }
            )
            return FlowRequest(flow: flow, steps: ["Choose who", "Confirm the call"])
        default:
            return nil
        }
    }

    private func composeFlow(_ kind: ComposeKind, name: String?, message: String?, appName: String) -> FlowRequest {
        let recipient = name.flatMap { contacts.find($0) }
        let hasMessage = !(message ?? "").isEmpty
        var steps: [String] = []
        if recipient == nil { steps.append("Choose who") }
        if !hasMessage { steps.append("Say the message") }
        steps += ["Check it", "Open \(appName)"]
        return FlowRequest(
            flow: ComposeFlow(kind: kind, contacts: contacts, compose: compose, ai: makeAIService(), recipient: recipient, initialBody: message),
            steps: steps
        )
    }

    /// Describes what a consequential action will do, for the approval screen.
    func approvalRequest(for action: AssistantAction) async -> ApprovalRequest {
        switch action {
        case .callContact(let name):
            guard let contact = contacts.find(name), let phone = contact.phone else {
                return ApprovalRequest(
                    title: "Call \(name)",
                    summary: "I could not find \(name) in your contacts. I know \(contacts.spokenDemoNames).",
                    confirmLabel: "Try anyway"
                )
            }
            return ApprovalRequest(
                title: "Call \(contact.name)",
                summary: "I will start a phone call to \(contact.name).",
                rows: [ApprovalRequest.Row(label: "Number", value: phone)],
                confirmLabel: "Call now"
            )
        case .emergency:
            let contact = contacts.emergencyContact
            return emergency.approvalRequest(contactName: contact.name, locationText: location.lastKnownDescription)
        case .callEmergencyServices:
            let number = Self.emergencyServicesNumber
            return ApprovalRequest(
                title: "Call emergency services",
                summary: "I will call \(number), the emergency services number for your region.",
                rows: [ApprovalRequest.Row(label: "Number", value: number)],
                caution: "Only confirm if you need urgent help from the police, an ambulance or the fire service.",
                confirmLabel: "Call \(number) now"
            )
        case .sendCheckIn:
            let contact = contacts.emergencyContact
            return ApprovalRequest(
                title: "Send a check-in",
                summary: "I will open Messages with a short text to \(contact.name) saying you are okay. You tap Send there.",
                rows: [
                    ApprovalRequest.Row(label: "To", value: contact.name),
                    ApprovalRequest.Row(label: "Message", value: "Checking in from ECHO: I'm okay."),
                ],
                confirmLabel: "Open Messages"
            )
        case .submitForm:
            let snapshot = await web.snapshot()
            let fields = snapshot?.elements.filter { $0.kind == "field" && $0.type != "password" } ?? []
            let rows = fields.prefix(8).map {
                ApprovalRequest.Row(label: $0.label, value: $0.value.isEmpty ? "empty" : $0.value)
            }
            let sensitive = snapshot?.hasPasswordField == true || fields.contains { $0.isSensitive }
            return ApprovalRequest(
                title: "Submit the form",
                summary: "I will submit the form on \(snapshot?.title ?? "this page").",
                rows: rows,
                caution: sensitive
                    ? "This looks like a sign-in or payment. Face ID will be required."
                    : "Submitting sends this information to the website. Only you can approve this step.",
                requiresBiometric: sensitive,
                confirmLabel: "Confirm and submit"
            )
        default:
            return ApprovalRequest(title: "Confirm", summary: "Do you want me to continue?")
        }
    }

    /// Runs one action and returns the short reply to speak. An empty reply means the feature speaks for itself.
    func perform(_ action: AssistantAction) async -> String {
        switch action {
        case .openScreen(let screen):
            router.open(screen)
            // In screen mode the screen announces itself when it appears; in voice-only mode nothing appears.
            return settings.interfaceMode == .voiceOnly ? screen.announcement : ""

        case .switchInterface(let mode):
            settings.interfaceMode = mode
            return mode == .voiceOnly
                ? "Voice only mode. The screen now shows just the status and the microphone. Say show the screen to go back."
                : "Screen and voice mode."

        case .describeScene, .takePhoto:
            return requestPhoto(.describe)
        case .readText:
            return requestPhoto(.readText)
        case .scanDocument:
            return requestPhoto(.scanDocument)
        case .identifyColor:
            return requestPhoto(.identifyColor)
        case .findObject(let target):
            return requestPhoto(.findObject(target))

        case .openWebsite(let name):
            router.open(.web)
            return web.open(name)
        case .describeWebPage:
            guard let snapshot = await web.snapshot() else {
                return "This page is not ready yet. Try again in a moment."
            }
            return (try? await makeAIService().summarizeWebPage(snapshot)) ?? MockAIService.summary(of: snapshot)
        case .readWebPage:
            guard let snapshot = await web.snapshot() else {
                return "This page is not ready yet. Try again in a moment."
            }
            web.startReading(snapshot.mainText)
            return ""
        case .clickElement(let target):
            guard let snapshot = await web.snapshot(), let element = snapshot.element(matching: target) else {
                return "I could not find \(target) on this page. Say what can I do here to hear the options."
            }
            if element.isSensitive {
                return "I will not press \(element.label) for you, because it looks like a sign-in or payment step. Please tap it yourself."
            }
            if element.submitsForm {
                return "\(element.label) sends a form. Say submit the form, and I will show you what will be sent first."
            }
            let clicked = await web.click(index: element.index)
            return clicked ? "Pressed \(element.label)." : "I could not press \(element.label)."
        case .typeInField(let target, let value):
            return await web.type(value, into: target)
        case .scrollPage(let down):
            await web.scroll(down: down)
            return down ? "Scrolling down." : "Scrolling up."
        case .submitForm:
            let submitted = await web.submitForm()
            return submitted ? "Form submitted." : "I could not find a form on this page."
        case .readLink(let number):
            guard let snapshot = await web.snapshot() else {
                return "This page is not ready yet. Try again in a moment."
            }
            let links = snapshot.links
            guard number >= 1, number <= links.count else {
                return "This page has \(links.count) links."
            }
            return "Link \(number) is \(links[number - 1].label)."
        case .nextHeading:
            return await web.nextHeading() ?? "There are no more headings below."

        case .callContact(let name):
            guard let contact = contacts.find(name), let phone = contact.phone else {
                return "I could not find \(name). I know \(contacts.spokenDemoNames)."
            }
            return placeCall(name: contact.name, phone: phone)

        case .emergency:
            let contact = contacts.emergencyContact
            guard let phone = contact.phone else { return "Your emergency contact has no phone number saved." }
            caregiver.log("Emergency call started")
            return emergency.startCall(phone: phone)

        case .callEmergencyServices:
            caregiver.log("Called emergency services")
            return placeCall(name: "emergency services", phone: Self.emergencyServicesNumber)

        case .sendCheckIn:
            return caregiver.sendCheckIn(to: contacts.emergencyContact.phone ?? "")

        case .whereAmI:
            let answer = await location.whereAmI()
            caregiver.log("Asked where they are")
            return answer

        case .dailyBriefing:
            return BriefingBuilder.build(
                timeOfDay: Self.timeOfDay(),
                reminders: reminders.todayItems(),
                unreadCount: inbox.unreadCount,
                weather: DemoData.weather
            )

        case .resetDemoData:
            inbox.resetDemoData()
            reminders.resetDemoData()
            caregiver.resetDemoData()
            history.clear()
            return "Demo data has been reset."

        case .composeEmail, .composeText, .readMessages, .setReminder:
            // These always run as dialogs through flow(for:).
            return ""
        }
    }

    /// Opens the camera and asks it to take the next photo for this purpose.
    /// Opens the camera and asks it to take the next photo for this purpose.
    /// In voice-only mode no screen is shown, so the photo is taken in the background instead.
    private func requestPhoto(_ purpose: CapturePurpose) -> String {
        if settings.interfaceMode == .voiceOnly {
            captureInBackground(purpose)
            return ""
        }
        camera.request(purpose)
        router.open(.camera)
        return ""
    }

    /// Called when a background photo starts (to say "hold still") and when it is ready (nil if the camera can't be used).
    var onBackgroundPhotoStarted: (() -> Void)?
    var onBackgroundPhoto: ((UIImage?, CapturePurpose) -> Void)?
    private lazy var backgroundCamera = CameraService()

    private func captureInBackground(_ purpose: CapturePurpose) {
        Task { [weak self] in
            guard let self else { return }
            let ready = await self.backgroundCamera.start()
            var image: UIImage?
            if ready {
                self.onBackgroundPhotoStarted?()
                // Give exposure and focus a moment to settle.
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                image = await self.backgroundCamera.capture()
            }
            self.backgroundCamera.stop()
            self.onBackgroundPhoto?(image, purpose)
        }
    }

    private func placeCall(name: String, phone: String) -> String {
        guard let url = EmergencyService.telURL(phone), UIApplication.shared.canOpenURL(url) else {
            return "Calls are not available on this device."
        }
        UIApplication.shared.open(url)
        caregiver.log("Called \(name)")
        return "Calling \(name)."
    }

    /// 911 in North America, 999 in the UK and Ireland, 000 in Australia, 112 elsewhere (it works across the EU and many other countries).
    static var emergencyServicesNumber: String {
        switch Locale.current.region?.identifier {
        case "US", "CA", "MX": return "911"
        case "GB", "IE": return "999"
        case "AU": return "000"
        default: return "112"
        }
    }

    private static func timeOfDay() -> String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "morning"
        case 12..<17: return "afternoon"
        case 17..<22: return "evening"
        default: return "night"
        }
    }
}
