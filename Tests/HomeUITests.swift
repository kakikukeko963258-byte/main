import XCTest

final class HomeUITests: XCTestCase {
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
        XCTAssertTrue(app.staticTexts["ページ 3"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.navigationBars.count, 0, "番号ページに標準の戻るバーを重ねない")
        capture("03-page")
        app.buttons["ホームへ戻る"].tap()
        XCTAssertTrue(app.buttons["フォルダを閉じる"].waitForExistence(timeout: 5))
        app.buttons["フォルダを閉じる"].tap()
        app.buttons["アプリ 32"].tap()
        XCTAssertTrue(app.staticTexts["ページ 32"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.navigationBars.count, 0)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        XCTAssertTrue(app.buttons["アプリ 32"].waitForExistence(timeout: 5), "戻るスワイプが動く")
        app.buttons["アプリ 32"].tap()
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
        XCTAssertTrue(app.staticTexts["ページ 2"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
