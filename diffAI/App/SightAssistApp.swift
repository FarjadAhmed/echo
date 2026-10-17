import SwiftUI

@main
struct SightAssistApp: App {
    private let environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment.settings)
                .environmentObject(environment.router)
                .environmentObject(environment.speechOutput)
                .environmentObject(environment.permissions)
                .environmentObject(environment.camera)
                .environmentObject(environment.web)
                .environmentObject(environment.history)
                .environmentObject(environment.contacts)
                .environmentObject(environment.compose)
                .environmentObject(environment.inbox)
                .environmentObject(environment.reminders)
                .environmentObject(environment.location)
                .environmentObject(environment.emergency)
                .environmentObject(environment.caregiver)
                .environmentObject(environment.conversation)
                #if DEBUG
                .task { await LiveSelfTest.runIfRequested(environment) }
                #endif
        }
    }
}
