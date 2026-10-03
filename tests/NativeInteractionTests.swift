import XCTest

final class NativeInteractionTests: XCTestCase {
  private let app = XCUIApplication(bundleIdentifier: "app.muwa.nasheeds")

  override func setUpWithError() throws { continueAfterFailure = false }

  private func shot(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private var queueButtons: [XCUIElement] {
    app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "queue-play-")).allElementsBoundByIndex
  }

  func testWholeQueueRowMovePersistsAndKeepsCurrentTrack() {
    app.launchArguments = ["--audit-player", "--audit-queue", "--audit-interactions"]
    app.launch()
    XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "queue-play-")).firstMatch.waitForExistence(timeout: 30))
    let before = queueButtons.map(\.identifier)
    XCTAssertGreaterThanOrEqual(before.count, 3)
    // Move the row containing artwork, metadata and controls using the system
    // reorder handle. This exercises UIKit's real lift/move/drop interaction.
    let firstCell = app.cells.containing(.button, identifier: before[0]).firstMatch
    let thirdCell = app.cells.containing(.button, identifier: before[2]).firstMatch
    XCTAssertTrue(firstCell.exists && thirdCell.exists)
    shot("queue-before-move")
    let start = firstCell.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5))
    let end = thirdCell.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.9))
    start.press(forDuration: 0.7, thenDragTo: end)
    let reordered = queueButtons.map(\.identifier)
    XCTAssertEqual(Array(reordered.prefix(3)), [before[1], before[2], before[0]])
    XCTAssertTrue(app.staticTexts["На паузе"].exists, "Moving a row started playback")
    shot("queue-after-move")
    app.terminate()
    app.launch()
    XCTAssertTrue(app.buttons[reordered[0]].waitForExistence(timeout: 30))
    XCTAssertEqual(queueButtons.map(\.identifier), reordered, "Row order did not survive restart")
    shot("queue-after-restart")
  }

  func testCreatePlaylistAddTracksAndReturnWithNativeNavigation() {
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
}
