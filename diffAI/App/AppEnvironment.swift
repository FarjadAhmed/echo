import Foundation
import UserNotifications

/// Creates and wires every service once. Views receive what they need as environment objects.
@MainActor
final class AppEnvironment {
    let settings: AppSettings
    let router: AppRouter
    let haptics: HapticsService
    let speechOutput: SpeechOutputCoordinator
    let listener: ListenService
    let permissions: PermissionManager
    let camera: CameraController
    let web: WebAssistantController
    let history: HistoryStore
    let contacts: ContactsDirectory
    let compose: ComposeCoordinator
    let inbox: InboxStore
    let reminders: ReminderStore
    let location: LocationService
    let emergency: EmergencyService
    let caregiver: CaregiverStore
    let conversation: ConversationEngine
    /// The notification centre holds its delegate weakly, so it lives here.
    private let notificationDelegate: ReminderNotificationDelegate

    init() {
        let settings = AppSettings()
        let router = AppRouter()
        let speech = SpeechService()
        let speechOutput = SpeechOutputCoordinator(settings: settings, speech: speech)
        let listener = ListenService()
        let haptics = HapticsService(settings: settings)
        let permissions = PermissionManager()
        let camera = CameraController()
        let web = WebAssistantController(speechOutput: speechOutput)
        let history = HistoryStore()
        let contacts = ContactsDirectory()
        let compose = ComposeCoordinator()
        let inbox = InboxStore()
        let reminders = ReminderStore()
        let location = LocationService()
        let emergency = EmergencyService()
        let caregiver = CaregiverStore()

        // Live AI when a key is saved and the toggle is on; the offline demo otherwise. Decided per turn.
        let makeAIService: () -> any AIService = { AIProvider.current(settings: settings) }

        let actions = ActionExecutor(
            router: router,
            settings: settings,
            camera: camera,
            web: web,
            contacts: contacts,
            compose: compose,
            inbox: inbox,
            reminders: reminders,
            location: location,
            emergency: emergency,
            caregiver: caregiver,
            history: history,
            makeAIService: makeAIService
        )

        let conversation = ConversationEngine(
            settings: settings,
            speechOutput: speechOutput,
            listener: listener,
            haptics: haptics,
            permissions: permissions,
            actions: actions,
            history: history,
            makeAIService: makeAIService
        )

        self.settings = settings
        self.router = router
        self.haptics = haptics
        self.speechOutput = speechOutput
        self.listener = listener
        self.permissions = permissions
        self.camera = camera
        self.web = web
        self.history = history
        self.contacts = contacts
        self.compose = compose
        self.inbox = inbox
        self.reminders = reminders
        self.location = location
        self.emergency = emergency
        self.caregiver = caregiver
        self.conversation = conversation

        // Reminders that fire while ECHO is open are spoken; otherwise they show as normal banners.
        notificationDelegate = ReminderNotificationDelegate { text in
            conversation.announce(text)
        }
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }
}
