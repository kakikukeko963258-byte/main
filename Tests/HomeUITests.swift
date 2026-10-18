import XCTest

final class HomeUITests: XCTestCase {
    @MainActor
    func testChargingMonitor() {
        let app = XCUIApplication()
        app.launchArguments = ["-charging-direct-ui-test"]
        app.launch()
        XCTAssertTrue(app.navigationBars["充電モニター"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["charging-power"].exists)
        capture("charging-dashboard")
        app.swipeUp()
        app.swipeUp()
        let diagnostics = app.buttons["取得状況・USB-C PD・診断"]
        if !diagnostics.isHittable { app.swipeUp() }
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 5))
        diagnostics.tap()
        XCTAssertTrue(app.navigationBars["取得診断"].waitForExistence(timeout: 5))
        capture("charging-diagnostics")
        app.buttons["閉じる"].tap()
        app.buttons["ホームへ戻る"].tap()
        XCTAssertTrue(app.buttons["アプリ 1"].waitForExistence(timeout: 10))
    }
    @MainActor
    func testHomeAndFolderNavigation() {
        executionTimeAllowance = 180
        let app = XCUIApplication()
        app.launchArguments = ["-reset-home"]
        app.launch()
        XCTAssertTrue(app.buttons["アプリ 1"].waitForExistence(timeout: 10))
        let screen = app.frame
        let first = app.buttons["アプリ 1"].frame
        XCTAssertEqual(first.midX / screen.width, 145.5 / 947, accuracy: 0.002)
        let last = app.buttons["アプリ 32"].frame
        XCTAssertEqual(last.midX / screen.width, 801.0 / 947, accuracy: 0.002)
        // UIKit's page host has a device-dependent inset; preserve the accepted
        // layout and check its measured row pitch rather than the status-bar inset.
        XCTAssertEqual((last.minY - first.minY) / screen.height, 1190.0 / 2048, accuracy: 0.002)
        capture("01-home")
        app.buttons["ナビゲーション、5個のアプリ"].tap()
        XCTAssertTrue(app.buttons["アプリ 3"].waitForExistence(timeout: 5))
        capture("02-folder")
        app.buttons["アプリ 3"].tap()
        XCTAssertTrue(app.navigationBars["充電モニター"].waitForExistence(timeout: 5))
        capture("03-page")
        app.buttons["ホームへ戻る"].tap()
        XCTAssertTrue(app.buttons["フォルダを閉じる"].waitForExistence(timeout: 5))
        // Tap the visible outside area, as on the device. XCTest's invisible
        // accessibility-only close target can have an invalid computed hit point.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82)).tap()
        XCTAssertTrue(app.buttons["フォルダを閉じる"].waitForNonExistence(timeout: 5))
        capture("10-before-page32")
        tapVisibleIcon(app.buttons["アプリ 32"], in: app, expected: last)
        XCTAssertTrue(app.staticTexts["ページ 32"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.navigationBars.count, 0)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        XCTAssertTrue(app.buttons["アプリ 32"].waitForExistence(timeout: 5), "戻るスワイプが動く")
        tapVisibleIcon(app.buttons["アプリ 32"], in: app, expected: last)
        XCTAssertTrue(app.staticTexts["ページ 32"].waitForExistence(timeout: 5))
        app.buttons["ホームへ戻る"].tap()
        XCTAssertTrue(app.buttons["アプリ 1"].waitForExistence(timeout: 5))
        let moveSource = app.buttons["アプリ 13"]
        let moveTarget = app.buttons["アプリ 17"]
        let targetY = moveTarget.frame.minY
        let shiftedX = moveSource.frame.midX
        let shiftedY = moveSource.frame.minY
        moveSource.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.38))
            .press(forDuration: 0.45, thenDragTo: moveTarget.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.38)))
        XCTAssertTrue(app.buttons["完了"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["ホーム画面を編集"].exists)
        app.buttons["完了"].tap()
        XCTAssertFalse(app.buttons["完了"].exists)
        let stopped = app.buttons["アプリ 14"].frame
        Thread.sleep(forTimeInterval: 0.35)
        XCTAssertEqual(app.buttons["アプリ 14"].frame.minX, stopped.minX, accuracy: 0.1)
        XCTAssertEqual(app.buttons["アプリ 13"].frame.minY, targetY, accuracy: 3)
        XCTAssertEqual(app.buttons["アプリ 14"].frame.midX, shiftedX, accuracy: 3)
        XCTAssertEqual(app.buttons["アプリ 14"].frame.minY, shiftedY, accuracy: 3)
        capture("04-moved-icon")
        app.buttons["ナビゲーション、5個のアプリ"].tap()
        app.buttons["アプリ 3"].press(forDuration: 0.28)
        XCTAssertTrue(app.buttons["ホーム画面を編集"].waitForExistence(timeout: 5))
        capture("08-long-press-menu")
        app.buttons["ホーム画面を編集"].tap()
        for slot in 3...6 {
            let remove = app.buttons["アプリ \(slot) をフォルダから取り出す"]
            XCTAssertTrue(remove.waitForExistence(timeout: 5))
            remove.tap()
        }
        XCTAssertTrue(app.buttons["アプリ 7"].waitForExistence(timeout: 5))
        capture("05-single-app-name")
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["アプリ 7"].waitForExistence(timeout: 10))
        app.buttons["アプリ 7"].press(forDuration: 0.28)
        app.buttons["ホーム画面を編集"].tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78)).tap()
        XCTAssertFalse(app.buttons["完了"].exists)
        let still = app.buttons["アプリ 7"].frame
        Thread.sleep(forTimeInterval: 0.35)
        XCTAssertEqual(app.buttons["アプリ 7"].frame.minX, still.minX, accuracy: 0.1)
        app.buttons["アプリ 7"].press(forDuration: 0.28)
        app.buttons["ホーム画面を編集"].tap()
        let removeHome = app.buttons["7をホーム画面から取り除く"]
        XCTAssertTrue(removeHome.waitForExistence(timeout: 5))
        capture("06-edit-minus")
        removeHome.tap()
        app.buttons["ホーム画面から取り除く"].tap()
        app.buttons["完了"].tap()
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["検索"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["アプリ 7"].exists)
        app.buttons["検索"].tap()
        let searchSeven = app.buttons["検索アプリ 7"]
        XCTAssertTrue(searchSeven.waitForExistence(timeout: 5))
        searchSeven.press(forDuration: 0.7)
        app.buttons["ホーム画面に戻す"].tap()
        app.buttons["完了"].tap()
        XCTAssertTrue(app.buttons["アプリ 7"].waitForExistence(timeout: 5))
    }
    @MainActor
    func testPCFileBridgePageAndReturn() {
        addUIInterruptionMonitor(withDescription: "Local network access") { alert in
            for name in ["Allow", "許可", "OK"] {
                if alert.buttons[name].exists { alert.buttons[name].tap(); return true }
            }
            return false
        }
        let app = XCUIApplication()
        app.launchArguments = ["-reset-home"]
        app.launch()
        let first = app.buttons["アプリ 1"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap()
        XCTAssertTrue(app.navigationBars["PC File Bridge"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.navigationBars["PC File Bridge"].buttons.count, 1, "独自のホームボタンだけを表示する")
        XCTAssertTrue(app.textFields["PC画面の6桁コード"].exists)
        XCTAssertTrue(app.buttons["ペアリングしてFilesに追加"].exists)
        capture("07-pc-file-bridge")
        app.buttons["ホームへ戻る"].tap()
        XCTAssertTrue(app.buttons["アプリ 2"].waitForExistence(timeout: 5))
        app.buttons["アプリ 2"].tap()
        XCTAssertTrue(app.navigationBars["写真リスニング"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testListeningChapterPlaybackAndHighlight() {
        let app = XCUIApplication()
        // Isolate playback/reading from the launch morph's stale simulator AX
        // coordinates. Slot-2 integration is checked by the bridge/return test.
        app.launchArguments = ["-reset-home", "-listening-direct-ui-test"]
        app.launch()
        XCTAssertTrue(app.navigationBars["写真リスニング"].waitForExistence(timeout: 10))
        let chapterPicker = app.buttons["listening-chapter-picker"]
        let expanded = NSPredicate { _, _ in chapterPicker.frame.height >= 25 && chapterPicker.frame.width >= 80 }
        expectation(for: expanded, evaluatedWith: chapterPicker)
        waitForExpectations(timeout: 15)
        chapterPicker.tap()
        app.buttons["第2章"].tap()
        let play = app.buttons["再生"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        XCTAssertTrue(app.buttons["一時停止"].waitForExistence(timeout: 5))
        let reading = app.textViews["listening-reading-text"]
        let highlighted = NSPredicate { _, _ in
            guard let value = reading.value as? String else { return false }
            return !value.isEmpty && value.count < 40
        }
        expectation(for: highlighted, evaluatedWith: reading)
        waitForExpectations(timeout: 10)
        app.swipeUp()
        capture("11-listening-highlight")
        app.swipeDown()
        app.buttons["一時停止"].tap()
        app.buttons["ホームへ戻る"].tap()
        XCTAssertTrue(app.buttons["アプリ 1"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func tapVisibleIcon(_ button: XCUIElement, in app: XCUIApplication, expected: CGRect) {
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        let frame = button.frame
        XCTAssertEqual(frame.midX, expected.midX, accuracy: 1)
        XCTAssertEqual(frame.minY, expected.minY, accuracy: 1)
        let point = CGPoint(x: expected.midX, y: expected.minY + expected.height * 0.35)
        guard frame.width > 0, frame.height > 0, app.frame.contains(point) else {
            XCTFail("アイコンの実際のタップ位置が画面内にある")
            return
        }
        // iOS 26 sometimes reports hit point (-1,-1) for a SwiftUI Button
        // overlaid by our UIKit touch surface after dismissing a folder.
        // Tap the visible icon itself; still require the real page to appear.
        print("Visible icon tap: \(button.label), frame=\(frame), screen point=\(point)")
        let screen = app.frame
        app.coordinate(withNormalizedOffset: CGVector(dx: (point.x - screen.minX) / screen.width,
                                                      dy: (point.y - screen.minY) / screen.height)).tap()
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
