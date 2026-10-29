import XCTest
import SwiftUI
@testable import Cortex

@MainActor
private final class DeepDiveNavigationDriver:ObservableObject {
    @Published var path:[String] = []
    var appearances = 0
}
private struct DeepDiveNavigationHarness:View {
    @ObservedObject var driver:DeepDiveNavigationDriver
    var body:some View {
        NavigationStack(path:$driver.path) {
            Text("Home").navigationDestination(for:String.self) {route in
                LibraryView().onAppear {driver.appearances += 1}
            }
        }.environmentObject(LibraryStore()).environmentObject(AccountSession())
    }
}
@MainActor
final class NavigationTests:XCTestCase {
    func testDeepDiveCanOpenAndReturnRepeatedlyInTheRootPath() async throws {
        let driver = DeepDiveNavigationDriver()
        let host = UIHostingController(rootView:DeepDiveNavigationHarness(driver:driver))
        let window = UIWindow(frame:CGRect(x:0,y:0,width:744,height:1133));window.rootViewController = host;window.makeKeyAndVisible()
        defer {window.isHidden = true}
        try await Task.sleep(nanoseconds:200_000_000)
        for cycle in 1...3 {
            driver.path = ["Deep dive"]
            let deadline = Date().addingTimeInterval(5)
            while driver.appearances < cycle && Date()<deadline {try await Task.sleep(nanoseconds:100_000_000)}
            XCTAssertGreaterThanOrEqual(driver.appearances,cycle,"Deep Dive must actually appear on each root-path navigation")
            host.view.layoutIfNeeded()
            driver.path = []
            try await Task.sleep(nanoseconds:500_000_000)
        }
    }
}
