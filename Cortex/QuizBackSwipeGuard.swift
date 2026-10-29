import SwiftUI
import UIKit

// Unfinished quizzes use the visible Back confirmation. Disable the edge-swipe
// route while active so it cannot bypass Pause / Exit without saving.
struct QuizBackSwipeGuard:UIViewControllerRepresentable {
    let blocked:Bool
    func makeUIViewController(context:Context) -> Controller {Controller()}
    func updateUIViewController(_ controller:Controller,context:Context) {
        controller.blocked = blocked
        DispatchQueue.main.async {[weak controller] in controller?.apply()}
    }
    static func dismantleUIViewController(_ controller:Controller,coordinator:()) {controller.restore()}
    final class Controller:UIViewController {
        var blocked = false
        private weak var gesture:UIGestureRecognizer?
        private var previous:Bool?
        private var isVisible = false
        override func viewDidAppear(_ animated:Bool) {super.viewDidAppear(animated);isVisible = true;apply()}
        override func viewDidDisappear(_ animated:Bool) {super.viewDidDisappear(animated);isVisible = false;restore()}
        func apply() {
            guard isVisible else {return}
            guard blocked else {restore();return}
            guard let pop = navigationController?.interactivePopGestureRecognizer ?? parent?.navigationController?.interactivePopGestureRecognizer else {return}
            if gesture !== pop {restore();gesture = pop;previous = pop.isEnabled}
            pop.isEnabled = false
        }
        func restore() {
            if let previous {gesture?.isEnabled = previous}
            previous = nil;gesture = nil
        }
    }
}
