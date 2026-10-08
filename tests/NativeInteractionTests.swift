import XCTest
import UIKit
import ImageIO

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
    app.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", "queue-row-"))
  }
  private var queueButtons: [XCUIElement] { queueQuery.allElementsBoundByIndex }

  func testPortraitArtworkFillsThePlayerFrame() throws {
    app.launchArguments = ["--audit-player", "--audit-portrait"]
    app.launch()
    XCTAssertTrue(app.staticTexts["Portrait crop check"].waitForExistence(timeout: 30))
    // Keep the original framebuffer for the pixel checker. The controlled
    // portrait has a uniform teal colour, so side bars cannot hide in artwork.
    let cover = app.otherElements["player-artwork-frame"]
    XCTAssertTrue(cover.waitForExistence(timeout: 15))
    let loaded = app.images["Обложка нашида"].firstMatch
    XCTAssertTrue(loaded.waitForExistence(timeout: 15))
    shot("portrait-artwork-filled-frame")
    let frame = cover.frame
    let image = app.screenshot().image
    guard let cg = image.cgImage else { return XCTFail("Native cover screenshot missing pixels") }
    let width = cg.width, height = cg.height
    var rgba = [UInt8](repeating: 0, count: width * height * 4)
    let colourSpace = CGColorSpaceCreateDeviceRGB()
    let drawn = rgba.withUnsafeMutableBytes { bytes -> Bool in
      guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colourSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
      context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height)); return true
    }
    XCTAssertTrue(drawn)
    func sample(_ fraction: Double) -> [Int] {
      let x = Int((frame.minX + frame.width * fraction) / app.frame.width * Double(width))
      let y = Int(frame.midY / app.frame.height * Double(height))
      XCTAssertTrue(x >= 0 && x < width && y >= 0 && y < height)
      let offset = (min(height - 1, max(0, y)) * width + min(width - 1, max(0, x))) * 4
      return rgba[offset..<offset+3].map(Int.init)
    }
    let centre = sample(0.5)
    XCTAssertGreaterThan(centre[1], 100); XCTAssertGreaterThan(centre[2], 100)
    for side in [0.05, 0.95] {
      let edge = sample(side)
      for channel in 0..<3 { XCTAssertLessThan(abs(edge[channel] - centre[channel]), 12, "Portrait artwork left an empty side bar") }
    }
    let proof: [String: Any] = ["x":frame.minX,"y":frame.minY,"width":frame.width,"height":frame.height,"screenWidth":app.frame.width,"screenHeight":app.frame.height]
    let data = try JSONSerialization.data(withJSONObject: proof, options: .sortedKeys)
    let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
    attachment.name = "portrait-artwork-frame-proof"; attachment.lifetime = .keepAlways; add(attachment)
  }

  func testPlayRemainsTappableWhileBuffering() throws {
    app.launchArguments = ["--audit-player", "--audit-buffering"]
    app.launch()
    let play = app.buttons["player-toggle"]
    XCTAssertTrue(play.waitForExistence(timeout: 30))
    let loading = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Загрузка аудио"), object: play)
    XCTAssertEqual(XCTWaiter.wait(for: [loading], timeout: 10), .completed)
    XCTAssertTrue(play.isHittable)
    XCTAssertFalse(app.staticTexts["Загружаем аудио…"].exists)
    shot("buffering-ring-play-tappable")
    play.tap()
    XCTAssertEqual(play.label, "Воспроизвести")
    XCTAssertEqual(play.value as? String, "На паузе")
    shot("buffering-ring-dismissed-after-pause")
  }

  func testPopularPagesMoveForwardAndBack() throws {
    app.launchArguments = ["--audit-home"]
    app.launch()
    let pages = app.scrollViews["popular-pages"]
    XCTAssertTrue(pages.waitForExistence(timeout: 30))
    for _ in 0..<3 { if !pages.isHittable { app.scrollViews.firstMatch.swipeUp() } }
    XCTAssertTrue(pages.isHittable)
    shot("popular-first-page")
    pages.swipeLeft()
    let nextPage = app.otherElements["popular-page-1"]
    let arrived = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      nextPage.exists && abs(nextPage.frame.midX - pages.frame.midX) < 20
    }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [arrived], timeout: 10), .completed)
    shot("popular-next-page")
    pages.swipeRight()
    let firstPage = app.otherElements["popular-page-0"]
    let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      firstPage.exists && abs(firstPage.frame.midX - pages.frame.midX) < 20
    }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 10), .completed)
    shot("popular-returned-page")
  }

  func testPlayerButtonsAndBothSubtitleEntrypointsShareState() throws {
    app.launchArguments = ["--audit-player", "--audit-ai"]
    app.launch()
    let subtitles = app.buttons["player-subtitles"]
    XCTAssertTrue(subtitles.waitForExistence(timeout: 30))
    XCTAssertTrue(subtitles.isHittable)
    XCTAssertEqual(subtitles.label, "Скрыть субтитры")
    subtitles.tap()
    XCTAssertEqual(subtitles.label, "Показать субтитры")
    app.buttons["player-menu"].tap()
    let menuCaption = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Показать субтитры", "player-subtitles")).firstMatch
    XCTAssertTrue(menuCaption.waitForExistence(timeout: 10))
    menuCaption.tap()
    XCTAssertEqual(subtitles.label, "Скрыть субтитры")
    XCTAssertTrue(app.buttons["Субтитры. Открыть полный текст"].waitForExistence(timeout: 10))
    let shuffle = app.buttons["player-shuffle"]
    XCTAssertEqual(shuffle.value as? String, "Выключено")
    shuffle.tap()
    XCTAssertEqual(shuffle.value as? String, "Включено")
    shuffle.tap()
    XCTAssertEqual(shuffle.value as? String, "Выключено")
    let repeatButton = app.buttons["player-repeat"]
    for expected in ["Вся очередь", "Один нашид", "Выключено"] {
      repeatButton.tap()
      XCTAssertEqual(repeatButton.value as? String, expected)
    }
    shot("player-buttons-and-arabic-subtitles")
    app.buttons["player-queue"].tap()
    XCTAssertTrue(queueQuery.firstMatch.waitForExistence(timeout: 10))
    shot("player-queue-opened-by-button")
  }

  func testHomeHasNoToolbarLogoAfterNativeTitleCollapses() throws {
    app.launchArguments = ["--audit-home"]
    app.launch()
    XCTAssertTrue(app.navigationBars["Главная"].waitForExistence(timeout: 30))
    XCTAssertTrue(app.buttons["Поиск"].exists)
    XCTAssertFalse(app.images["Muwa"].exists, "Removed toolbar logo returned")
    shot("home-before-scroll-no-logo")
    app.scrollViews.firstMatch.swipeUp()
    XCTAssertTrue(app.navigationBars["Главная"].exists)
    XCTAssertFalse(app.images["Muwa"].exists)
    shot("home-after-scroll-no-edge-blur")
  }

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
    let firstCell = app.cells[before[0]]
    let thirdCell = app.cells[before[2]]
    XCTAssertTrue(firstCell.exists && thirdCell.exists)
    shot("queue-before-move")
    let handle = firstCell.buttons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", "Reorder", "Reorder ")).firstMatch
    XCTAssertTrue(handle.exists)
    XCTAssertTrue(handle.isHittable)
    let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    // UIKit positions the lifted cell by its centre. Dropping at the third
    // cell's bottom crosses the fourth row's insertion threshold.
    let end = thirdCell.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5))
    start.press(forDuration: 0.8, thenDragTo: end, withVelocity: .slow,
                thenHoldForDuration: 0.5)
    let expected = [before[1], before[2], before[0]]
    // The native table commits its new accessibility order asynchronously.
    // Wait for the actual drop rather than inspecting the previous snapshot;
    // retain the real gesture and exact order/persistence assertions.
    let moved = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
      Array(queueButtons.map(\.identifier).prefix(3)) == expected
    }, object: nil)
    let dropResult = XCTWaiter.wait(for: [moved], timeout: 10)
    shot("queue-after-drop")
    XCTAssertEqual(dropResult, .completed, "Native row drag did not commit the expected order")
    let reordered = queueButtons.map(\.identifier)
    XCTAssertEqual(Array(reordered.prefix(3)), expected)
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

  func testShiftedSubtitleRailOpensAndClosesNativeReader() throws {
    // The cached document is seeded only in the disposable review app. Omit
    // --audit-ai-expanded: the production rail's own button must open the reader.
    app.launchArguments = ["--audit-player", "--audit-ai"]
    app.launch()
    let rail = app.buttons["Субтитры. Открыть полный текст"].firstMatch
    let reader = app.navigationBars["Оригинал и перевод"].firstMatch
    let follow = app.switches["Следить"].firstMatch
    XCTAssertTrue(rail.waitForExistence(timeout: 30))
    let ready = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", "Оригинальный текст доступен"), object: rail)
    XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed,
                   "The actual cached subtitle document did not populate the rail")
    XCTAssertTrue(rail.isHittable)
    XCTAssertFalse(reader.exists, "The fixture opened the reader without a real rail tap")
    XCTAssertFalse(follow.exists)
    let railFrame = rail.frame
    XCTAssertGreaterThan(min(railFrame.width, railFrame.height), 20)
    XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(railFrame),
                  "The shifted caption rail moved outside the safe application viewport")
    // The right edge exercises the part of the rail beyond the original square
    // cover. A contentShape confined to that square used to swallow this tap.
    let tapPoint = CGPoint(x: railFrame.minX + railFrame.width * 0.95,
                           y: railFrame.midY)
    shot("subtitle-rail-before-tap")
    rail.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    XCTAssertTrue(reader.waitForExistence(timeout: 10), "Tapping the actual rail did not open the native reader")
    XCTAssertTrue(follow.waitForExistence(timeout: 10), "The native reader's playback-follow control is missing")
    XCTAssertTrue(follow.isHittable)
    shot("subtitle-reader-opened-by-tap")
    let proof: [String: Any] = [
      "method": "Native AI subtitle rail coordinate tap without auto-expanded fixture",
      "launchArguments": app.launchArguments,
      "railValue": rail.value as? String ?? "",
      "railFrame": ["x": Double(railFrame.minX), "y": Double(railFrame.minY),
                    "width": Double(railFrame.width), "height": Double(railFrame.height)],
      "tapPoint": ["x": Double(tapPoint.x), "y": Double(tapPoint.y)],
      "readerNavigationTitleVisible": reader.exists,
      "followControlVisible": follow.exists && follow.isHittable,
    ]
    let data = try JSONSerialization.data(withJSONObject: proof, options: .sortedKeys)
    let evidence = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
    evidence.name = "subtitle-reader-opened-by-tap-proof"
    evidence.lifetime = .keepAlways
    add(evidence)
    let done = reader.buttons["Готово"].firstMatch
    XCTAssertTrue(done.waitForExistence(timeout: 5))
    XCTAssertTrue(done.isHittable)
    done.tap()
    // Preserve the actual post-tap state even when a hosted gesture fails.
    shot("subtitle-reader-after-close-tap")
    XCTAssertTrue(rail.waitForExistence(timeout: 10))
    let closed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      !reader.exists && !follow.exists && rail.isHittable
    }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 10), .completed,
                   "Closing the reader did not return to the native subtitle rail")
    shot("subtitle-rail-after-reader-dismiss")
  }

  private func rotationShot(_ name: String, landscape: Bool,
                            visibleElement: XCUIElement) throws {
    // XCUIScreen preserves the complete natural framebuffer and its own EXIF
    // orientation. XCUIApplication.screenshot cropped that rotated framebuffer
    // incorrectly on the iOS 27 runner; do not clip or rewrite the native pixels.
    let frameReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      let frame = self.app.frame
      return min(frame.width, frame.height) > 100
        && (landscape ? frame.width > frame.height : frame.height > frame.width)
    }, object: nil)
    let waitResult = XCTWaiter.wait(for: [frameReady], timeout: 30)
    let frame = app.frame
    let deviceOrientation = XCUIDevice.shared.orientation
    let controlVisible = visibleElement.exists && visibleElement.isHittable
    let controlFrame = visibleElement.frame
    let controlFullyInside = min(controlFrame.width, controlFrame.height) > 0
      && frame.insetBy(dx: -1, dy: -1).contains(controlFrame)
    let screenshot = XCUIScreen.main.screenshot()
    func keepPNG(_ screenshot: XCUIScreenshot, _ label: String) {
      let attachment = XCTAttachment(data: screenshot.pngRepresentation,
                                     uniformTypeIdentifier: "public.png")
      attachment.name = label
      attachment.lifetime = .keepAlways
      add(attachment)
    }
    // Preserve original bytes and provenance before assertions can terminate the
    // test, so an orientation failure is reviewable instead of losing its PNG.
    keepPNG(screenshot, name)
    func pixelInfo(_ screenshot: XCUIScreenshot) throws -> [String: Int] {
      let png = screenshot.pngRepresentation
      guard png.count >= 24,
            png.prefix(8) == Data([137, 80, 78, 71, 13, 10, 26, 10]),
            let source = CGImageSourceCreateWithData(png as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
        throw NSError(domain: "MuwaRotationVerification", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Expected an unmodified native PNG"])
      }
      let encodedWidth = png[16..<20].reduce(0) { ($0 << 8) | Int($1) }
      let encodedHeight = png[20..<24].reduce(0) { ($0 << 8) | Int($1) }
      let orientation = (properties[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue ?? 1
      // EXIF 5-8 explicitly transpose the encoded axes. This uses the PNG's own
      // metadata; never infer a pixel rotation from the requested device state.
      let transposed = (5...8).contains(orientation)
      return ["encodedWidth":encodedWidth, "encodedHeight":encodedHeight,
              "exifOrientation":orientation,
              "uiImageOrientation":screenshot.image.imageOrientation.rawValue,
              "displayWidth":transposed ? encodedHeight : encodedWidth,
              "displayHeight":transposed ? encodedWidth : encodedHeight]
    }
    let pixels = try pixelInfo(screenshot)
    let width = pixels["displayWidth"]!
    let height = pixels["displayHeight"]!
    let imageRatio = Double(width) / Double(height)
    let frameRatio = Double(frame.width) / Double(frame.height)
    let proof: [String: Any] = [
      "method": "XCUIDevice.orientation and unmodified XCUIScreen PNG with its own EXIF orientation",
      "screen": name, "landscape": landscape, "width": width, "height": height,
      "deviceOrientation": deviceOrientation.rawValue,
      "appFrameWidth": Double(frame.width), "appFrameHeight": Double(frame.height),
      "nativeControlVisible": controlVisible,
      "controlFrame": ["x":Double(controlFrame.minX), "y":Double(controlFrame.minY),
                       "width":Double(controlFrame.width), "height":Double(controlFrame.height)],
      "controlFullyInsideApp":controlFullyInside,
      "unmodifiedPNG": pixels, "captureSource":"XCUIScreen.main.screenshot",
      "displayAspectRatio":imageRatio, "appFrameAspectRatio":frameRatio,
      "frameOrientationReady": waitResult == .completed,
    ]
    let data = try JSONSerialization.data(withJSONObject: proof, options: .sortedKeys)
    let evidence = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
    evidence.name = name + "-proof"
    evidence.lifetime = .keepAlways
    add(evidence)
    XCTAssertEqual(waitResult, .completed, "Muwa did not adopt the actual device orientation")
    XCTAssertTrue(controlVisible, "The native screen control disappeared after rotation")
    XCTAssertTrue(controlFullyInside, "The native screen control moved outside the application")
    XCTAssertEqual(imageRatio, frameRatio, accuracy: 0.01,
                   "The native PNG display aspect must match the actual application frame")
    XCTAssertGreaterThan(min(width, height), 100)
    if landscape {
      XCTAssertTrue(deviceOrientation == .landscapeLeft || deviceOrientation == .landscapeRight,
                    "The actual device must be in landscape")
      XCTAssertGreaterThan(width, height, "A portrait application PNG cannot prove landscape")
    } else {
      XCTAssertEqual(deviceOrientation, .portrait)
      XCTAssertGreaterThan(height, width, "Expected a portrait native application PNG")
    }
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
