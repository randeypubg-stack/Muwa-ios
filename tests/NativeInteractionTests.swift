import XCTest
import UIKit

final class NativeInteractionTests: XCTestCase {
  private let app = XCUIApplication(bundleIdentifier: "app.muwa.nasheeds")

  override func setUpWithError() throws {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
  }

  override func tearDownWithError() throws {
    app.terminate()
    XCUIDevice.shared.orientation = .portrait
  }

  private func shot(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private var queueQuery: XCUIElementQuery {
    app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND NOT label BEGINSWITH %@", "queue-row-", "Удалить"))
  }
  private var queueButtons: [XCUIElement] { queueQuery.allElementsBoundByIndex }

  func testWholeQueueRowMovePersistsAndKeepsCurrentTrack() throws {
    try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone,
                  "Queue interaction is covered on the iPhone; tablet jobs verify real device rotation")
    app.launchArguments = ["--audit-player", "--audit-queue", "--audit-interactions"]
    app.launch()
    XCTAssertTrue(queueQuery.firstMatch.waitForExistence(timeout: 30))
    let before = queueButtons.map(\.identifier)
    XCTAssertGreaterThanOrEqual(before.count, 3)
    // Move the row containing artwork, metadata and controls using the system
    // reorder handle. This exercises UIKit's real lift/move/drop interaction.
    let firstCell = app.cells.containing(.button, identifier: before[0]).firstMatch
    let thirdCell = app.cells.containing(.button, identifier: before[2]).firstMatch
    XCTAssertTrue(firstCell.exists && thirdCell.exists)
    shot("queue-before-move")
    let handle = firstCell.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Reorder ")).firstMatch
    XCTAssertTrue(handle.exists)
    let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    let end = thirdCell.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.95))
    start.press(forDuration: 0.7, thenDragTo: end)
    let reordered = queueButtons.map(\.identifier)
    XCTAssertEqual(Array(reordered.prefix(3)), [before[1], before[2], before[0]])
    XCTAssertTrue(app.staticTexts["На паузе"].exists, "Moving a row started playback")
    shot("queue-after-move")
    app.terminate()
    app.launch()
    XCTAssertTrue(queueQuery.firstMatch.waitForExistence(timeout: 30))
    XCTAssertEqual(queueButtons.map(\.identifier), reordered, "Row order did not survive restart")
    shot("queue-after-restart")
  }

  func testCreatePlaylistAddTracksAndReturnWithNativeNavigation() throws {
    try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone,
                  "Playlist interaction is covered on the iPhone; tablet jobs verify real device rotation")
    app.launchArguments = ["--audit-library-empty"]
    app.launch()
    XCTAssertTrue(app.buttons["Создать плейлист"].waitForExistence(timeout: 30))
    XCTAssertEqual(app.buttons.matching(identifier: "Создать плейлист").count, 1)
    shot("playlists-empty")
    app.buttons["Создать плейлист"].tap()
    let field = app.textFields["playlist-name"]
    XCTAssertTrue(field.waitForExistence(timeout: 10))
    shot("playlist-create")
    field.tap()
    field.typeText("For the road")
    app.buttons["playlist-create"].tap()
    let playlist = app.staticTexts["For the road"]
    XCTAssertTrue(playlist.waitForExistence(timeout: 10))
    playlist.tap()
    XCTAssertTrue(app.buttons["Выбрать нашиды"].waitForExistence(timeout: 10))
    shot("playlist-detail-empty")
    app.buttons["Выбрать нашиды"].tap()
    let row = app.cells.firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 10))
    row.tap()
    XCTAssertTrue(app.buttons["Добавить 1"].isEnabled)
    shot("playlist-track-picker")
    app.buttons["Добавить 1"].tap()
    XCTAssertTrue(app.buttons["Слушать подборку"].waitForExistence(timeout: 10))
    shot("playlist-detail-populated")
    app.navigationBars.buttons["Плейлисты"].tap()
    XCTAssertTrue(app.staticTexts["For the road"].waitForExistence(timeout: 10))
    app.terminate()
    app.launchArguments = ["--audit-library"]
    app.launch()
    XCTAssertTrue(app.staticTexts["For the road"].waitForExistence(timeout: 30))
    shot("playlist-after-restart")
    app.navigationBars.buttons["Библиотека"].tap()
    XCTAssertTrue(app.staticTexts["Ваша библиотека"].waitForExistence(timeout: 10))
  }

  private func rotationShot(_ name: String, landscape: Bool,
                            visibleElement: XCUIElement) throws {
    // The app frame must follow the physical Simulator device, not a fixture's
    // requested window geometry. Then verify the unmodified device PNG itself.
    let frameReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      let frame = self.app.frame
      return min(frame.width, frame.height) > 100
        && (landscape ? frame.width > frame.height : frame.height > frame.width)
    }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [frameReady], timeout: 30), .completed,
                   "Muwa did not adopt the actual device orientation")
    XCTAssertTrue(visibleElement.exists && visibleElement.isHittable,
                  "The native screen control disappeared after rotation")
    let screenshot = XCUIDevice.shared.screenshot()
    let png = screenshot.pngRepresentation
    guard png.count >= 24,
          png.prefix(8) == Data([137, 80, 78, 71, 13, 10, 26, 10]) else {
      XCTFail("Expected an actual device PNG")
      return
    }
    let width = png[16..<20].reduce(0) { ($0 << 8) | Int($1) }
    let height = png[20..<24].reduce(0) { ($0 << 8) | Int($1) }
    XCTAssertGreaterThan(min(width, height), 100)
    if landscape {
      XCTAssertGreaterThan(width, height, "A portrait PNG cannot prove landscape")
    } else {
      XCTAssertGreaterThan(height, width, "Expected a portrait device framebuffer")
    }
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
    let proof: [String: Any] = [
      "method": "XCUIDevice.orientation and unmodified device framebuffer",
      "screen": name, "landscape": landscape, "width": width, "height": height,
      "deviceOrientation": XCUIDevice.shared.orientation.rawValue,
      "appFrameWidth": app.frame.width, "appFrameHeight": app.frame.height,
      "nativeControlVisible": visibleElement.exists && visibleElement.isHittable,
    ]
    let data = try JSONSerialization.data(withJSONObject: proof, options: .sortedKeys)
    let evidence = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
    evidence.name = name + "-proof"
    evidence.lifetime = .keepAlways
    add(evidence)
  }

  func testHomeAndPlayerFollowActualDeviceRotation() throws {
    let device = XCUIDevice.shared
    app.launchArguments = ["--audit-home"]
    app.launch()
    let home = app.staticTexts["Нашиды без музыки"].firstMatch
    XCTAssertTrue(home.waitForExistence(timeout: 30))
    try rotationShot("rotation-home-portrait", landscape: false, visibleElement: home)
    device.orientation = .landscapeRight
    try rotationShot("rotation-home-landscape", landscape: true, visibleElement: home)
    app.terminate()

    device.orientation = .portrait
    // Deliberately omit --audit-landscape. XCTest must rotate the actual device
    // and the production layout must react to it without a geometry fixture.
    app.launchArguments = ["--audit-player"]
    app.launch()
    let position = app.sliders["Позиция воспроизведения"].firstMatch
    XCTAssertTrue(position.waitForExistence(timeout: 30))
    try rotationShot("rotation-player-portrait", landscape: false, visibleElement: position)
    device.orientation = .landscapeRight
    try rotationShot("rotation-player-landscape", landscape: true, visibleElement: position)
    device.orientation = .portrait
    try rotationShot("rotation-player-return-portrait", landscape: false, visibleElement: position)
  }
}
