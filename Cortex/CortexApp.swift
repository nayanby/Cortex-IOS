import SwiftUI
import GoogleSignIn

@main
struct CortexApp: App {
    @UIApplicationDelegateAdaptor(CortexAppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup {
            CortexRootView().onOpenURL { url in _ = GIDSignIn.sharedInstance.handle(url) }
        }
    }
}
