import SwiftUI
import GoogleSignIn

@main
struct CortexApp: App {
    @UIApplicationDelegateAdaptor(CortexAppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup {
            CortexRootView().preferredColorScheme(.light).onOpenURL { url in _ = GIDSignIn.sharedInstance.handle(url) }
        }
    }
}
