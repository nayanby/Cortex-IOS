import SwiftUI
import FirebaseAuth

struct CortexRootView: View {
    @StateObject private var session = AccountSession()
    @StateObject private var library = LibraryStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var started = false
    @State private var browsingOffline = false

    var body: some View {
        Group {
            if !started { ProgressView("Opening Cortex…") }
            else if OfflineLibrary.available { ConsumerHomeView() }
            else if !session.configurationAvailable {
                #if DEBUG
                if session.configurationStatus == .rejectedConfiguration, !browsingOffline {
                    VStack(spacing: 20) {
                        ContentUnavailableView("Online notes unavailable", systemImage: "person.crop.circle.badge.exclamationmark",
                            description: Text("Install an updated CORTEX build to sign in. You can still browse the catalog and read imported files."))
                        Button("Browse offline") { browsingOffline = true }.buttonStyle(.borderedProminent)
                    }
                } else { ConsumerHomeView() }
                #else
                ContentUnavailableView("Cortex isn't ready on this build", systemImage: "book.closed",
                                       description: Text("Please install an updated build."))
                #endif
            } else if let profile = session.profile {
                ConsumerHomeView().id(profile.uid)
                    .task(id: profile) { await library.refresh(profile: profile) }
            } else if session.isRestoring { ProgressView("Restoring your account…") }
            else { ConsumerSignInView() }
        }
        .environmentObject(session).environmentObject(library)
        .tint(CortexStyle.ink)
        .task { session.start(); started = true }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, started { Task { await session.refresh() } }
        }
    }
}

private struct SignInPresentationAnchor: UIViewControllerRepresentable {
    let ready: (UIViewController) -> Void
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        DispatchQueue.main.async { ready(controller) }
        return controller
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) { }
}

struct ConsumerSignInView: View {
    @EnvironmentObject private var session: AccountSession
    @State private var presenter: UIViewController?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Welcome to Cortex").font(CortexStyle.title(28)).foregroundStyle(CortexStyle.ink)
                Text("Sign in with Google to get started.").font(.system(size: 15)).foregroundStyle(CortexStyle.muted)
                Button {
                    if let presenter { Task { await session.signInWithGoogle(presenting: presenter) } }
                } label: {
                    HStack(spacing: 10) {
                        Image("GoogleMark").resizable().frame(width: 24, height: 24)
                        Text("Continue with Google")
                    }.frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent).padding(.top, 16)
                .disabled(session.isSigningIn || presenter == nil)
                if session.isSigningIn { ProgressView("Signing in…").frame(maxWidth: .infinity) }
                if let error = session.errorMessage { Text(error).font(.callout).foregroundStyle(.red) }
                if session.configurationAvailable, Auth.auth().currentUser != nil, !session.isSigningIn {
                    Button("Retry account access") { Task { await session.refresh() } }
                    Button("Sign out") { session.signOut() }
                }
            }.padding(.horizontal, 28).padding(.top, 48)
        }
        .background(CortexStyle.background)
        .background(SignInPresentationAnchor { presenter = $0 }.frame(width: 0, height: 0))
    }
}

struct ConsumerAccountView: View {
    @EnvironmentObject private var session: AccountSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let profile = session.profile {
                    Section("Account") {
                        Text(profile.name.isEmpty ? "Cortex" : profile.name).font(CortexStyle.title(20))
                        Text(profile.email)
                        if !profile.institute.isEmpty { Text(profile.institute) }
                    }
                    Section("Access") {
                        Text(profile.isBeta ? "Beta" : profile.plan.capitalized)
                        if profile.plan.lowercased() == "trial", profile.hasFullAccess() {
                            let days = max(0, Int(ceil(Double(profile.trialStartedAt + ConsumerProfile.trialDuration - ConsumerProfile.millisecondsNow()) / 86_400_000)))
                            Text("\(days) days left in your trial")
                        } else if !profile.hasFullAccess() {
                            Text("You can read notes on the free plan. Study tools require full access.")
                        }
                        Button("Refresh account") { Task { await session.refresh() } }.disabled(session.isRestoring)
                    }
                    if let error = session.errorMessage { Text(error).foregroundStyle(.red) }
                    Button("Sign out", role: .destructive) { session.signOut(); dismiss() }
                }
            }.navigationTitle("Account").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { dismiss() } }
        }.tint(CortexStyle.ink)
    }
}
