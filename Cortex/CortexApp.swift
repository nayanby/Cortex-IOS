import SwiftUI

@main
struct CortexApp: App {
    @UIApplicationDelegateAdaptor(CortexAppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup { LibraryView() }
    }
}
