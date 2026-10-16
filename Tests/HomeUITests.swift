import XCTest

final class HomeUITests: XCTestCase {
    @MainActor
    func testHomeAndFolderNavigation() {
        let app = XCUIApplication()
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
        capture("03-page")
        app.buttons["ホームへ戻る"].tap()
        XCTAssertTrue(app.buttons["フォルダを閉じる"].waitForExistence(timeout: 5))
        app.buttons["フォルダを閉じる"].tap()
        app.buttons["アプリ 32"].tap()
        XCTAssertTrue(app.staticTexts["ページ 32"].waitForExistence(timeout: 5))
        app.buttons["ホームへ戻る"].tap()
        XCTAssertTrue(app.buttons["アプリ 1"].waitForExistence(timeout: 5))
        let moveSource = app.buttons["アプリ 13"]
        let moveTarget = app.buttons["アプリ 17"]
        let targetY = moveTarget.frame.minY
        moveSource.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.38))
            .press(forDuration: 0.45, thenDragTo: moveTarget.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.38)))
        XCTAssertTrue(app.buttons["完了"].waitForExistence(timeout: 5))
        app.buttons["完了"].tap()
        XCTAssertEqual(app.buttons["アプリ 13"].frame.minY, targetY, accuracy: 3)
        capture("04-moved-icon")
        app.buttons["ナビゲーション、5個のアプリ"].tap()
        app.buttons["アプリ 3"].press(forDuration: 0.5)
        for slot in 3...6 {
            let remove = app.buttons["アプリ \(slot) をフォルダから取り出す"]
            XCTAssertTrue(remove.waitForExistence(timeout: 5))
            remove.tap()
        }
        XCTAssertTrue(app.buttons["アプリ 7"].waitForExistence(timeout: 5))
        capture("05-single-app-name")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["アプリ 7"].waitForExistence(timeout: 10))
    }
    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
