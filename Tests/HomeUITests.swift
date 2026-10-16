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
        XCTAssertEqual(first.minY / screen.height, 163.0 / 2048, accuracy: 0.002)
        let last = app.buttons["アプリ 32"].frame
        XCTAssertEqual(last.midX / screen.width, 801.0 / 947, accuracy: 0.002)
        XCTAssertEqual(last.minY / screen.height, 1353.0 / 2048, accuracy: 0.002)
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
    }
    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
