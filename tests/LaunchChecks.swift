import Foundation
import Combine

@main
struct LaunchChecks {
  @MainActor static func main() {
    let launch = LaunchPresentation(skipIntro: false)
    precondition(launch.isVisible)
    precondition(launch.begin())
    precondition(!launch.begin(), "Second window replayed the intro")
    var updates = 0
    let subscription = launch.objectWillChange.sink { updates += 1 }
    launch.finish()
    launch.finish()
    precondition(!launch.isVisible && !launch.begin(), "Resume replayed the intro")
    precondition(updates == 1, "Repeated completion invalidated the root")
    let review = LaunchPresentation(skipIntro: true)
    precondition(!review.isVisible && !review.begin(), "Static fixtures are blocked by intro")
    subscription.cancel()
    print("PASS: one-time launch ownership, cancellation completion, resume and review bypass")
  }
}
