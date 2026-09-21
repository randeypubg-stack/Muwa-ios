import Foundation
import Combine

@main
struct TimelineChecks {
  @MainActor static func main() {
    let timeline = PlaybackTimeline()
    var notifications = 0
    let subscription = timeline.objectWillChange.sink { notifications += 1 }
    timeline.update(time: 0, duration: 100)
    precondition(notifications == 1)
    for _ in 0..<1000 { timeline.update(time: 0, duration: 100) }
    precondition(notifications == 1, "Unchanged values publish again")
    for i in 1...100 { timeline.update(time: Double(i), duration: 100) }
    precondition(notifications == 101, "Clock should publish exactly once per tick")
    precondition(timeline.snapshot.progress == 1)
    timeline.update(time: .nan, duration: .infinity)
    precondition(timeline.snapshot.time == 0 && timeline.snapshot.progress == 0)
    timeline.update(time: -5, duration: -10)
    precondition(timeline.snapshot.time == 0 && timeline.snapshot.duration == 0)
    timeline.update(time: 500, duration: 100)
    precondition(timeline.snapshot.progress == 1)
    withExtendedLifetime(subscription) {}
    print("PASS: one publication per clock tick, duplicate suppression, invalid-time handling, clamping")
  }
}
