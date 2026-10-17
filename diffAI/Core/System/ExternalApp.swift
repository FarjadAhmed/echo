import UIKit

/// Opens another app (Phone, Messages, Mail) through a URL. One place, so the debug self-test can
/// stay inside ECHO instead of being sent to the background.
@MainActor
enum ExternalApp {
    static func open(_ url: URL) {
        #if DEBUG
        if LiveSelfTest.isRunning {
            print("ECHOTEST OPEN URL: \(url.scheme ?? "")")
            return
        }
        #endif
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}
