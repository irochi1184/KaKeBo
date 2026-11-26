import XCTest

final class VoucherScreens: XCTestCase {
    func testReferenceScreens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        app.buttons["記録する"].firstMatch.tap()
        let field = app.textFields["金額"]
        XCTAssertTrue(field.waitForExistence(timeout: 6))
        field.tap()
        capture("01-entry", app)
        field.typeText("680")
        app.buttons["カフェ代"].firstMatch.tap()
        let memo = app.textViews.firstMatch
        if memo.exists {
            memo.tap()
            memo.typeText("コーヒー")
        } else {
            app.textFields["メモ（任意）"].tap()
            app.textFields["メモ（任意）"].typeText("コーヒー")
        }
        if app.buttons["完了"].firstMatch.isHittable { app.buttons["完了"].firstMatch.tap() }
        capture("02-filled", app)
        app.buttons["保存する"].tap()
        XCTAssertTrue(app.staticTexts["コーヒー"].firstMatch.waitForExistence(timeout: 6))
        capture("03-home", app)
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
