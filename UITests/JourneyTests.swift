import XCTest
final class JourneyTests:XCTestCase {
    @MainActor func testLibraryJourneyWithRealGestures() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--ui-fixtures"];app.launch()
        let focus=app.buttons["focused-album"]
        XCTAssertTrue(focus.waitForExistence(timeout:30));capture("01-Collection")
        let original=focus.label
        let orbit=app.otherElements["collection-orbit"]
        // Coordinate drags exercise the actual SwiftUI recognizer, not view state.
        let area=orbit.exists ? orbit:app
        area.coordinate(withNormalizedOffset:CGVector(dx:0.78,dy:0.28)).press(forDuration:0.05,thenDragTo:area.coordinate(withNormalizedOffset:CGVector(dx:0.18,dy:0.28)))
        XCTAssertNotEqual(focus.label,original);capture("02-Orbit-after-drag")
        focus.tap();XCTAssertTrue(app.staticTexts["THE RECORD"].waitForExistence(timeout:5));capture("03-Album")
        app.buttons["Back to collection"].firstMatch.tap()
        let mini=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","Open player for")).firstMatch
        XCTAssertTrue(mini.waitForExistence(timeout:5));mini.tap()
        let handle=app.buttons["player-dismiss"]
        XCTAssertTrue(handle.waitForExistence(timeout:5));capture("04-Player")
        app.buttons["Play"].firstMatch.tap();XCTAssertTrue(app.buttons["Pause"].firstMatch.waitForExistence(timeout:5));app.buttons["Pause"].firstMatch.tap()
        let scrubber=app.sliders.firstMatch;let oldPosition=scrubber.value as? String
        scrubber.adjust(toNormalizedSliderPosition:0.35);XCTAssertNotEqual(scrubber.value as? String,oldPosition);capture("04a-Seek")
        if app.buttons["Remove favorite"].exists { app.buttons["Remove favorite"].tap() };app.buttons["Favorite"].tap();XCTAssertTrue(app.buttons["Remove favorite"].waitForExistence(timeout:5))
        app.buttons["Open queue"].tap();XCTAssertTrue(app.navigationBars["Queue"].waitForExistence(timeout:5));capture("04b-Queue")
        app.buttons["Done"].firstMatch.tap();XCTAssertTrue(handle.waitForExistence(timeout:5))
        let start=handle.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
        start.press(forDuration:0.1,thenDragTo:start.withOffset(CGVector(dx:0,dy:25)),withVelocity:.slow,thenHoldForDuration:0.4)
        XCTAssertTrue(handle.exists,"Short drag should snap back")
        start.press(forDuration:0.1,thenDragTo:start.withOffset(CGVector(dx:0,dy:310)))
        XCTAssertTrue(mini.waitForExistence(timeout:5));capture("05-Dismissed")
        app.buttons["Search your collection"].firstMatch.tap()
        let field=app.textFields.firstMatch;XCTAssertTrue(field.waitForExistence(timeout:5))
        field.tap();field.typeText("Nights")
        XCTAssertTrue(app.staticTexts["Nights"].firstMatch.waitForExistence(timeout:5));capture("06-Local-search")
        app.buttons["Songs"].firstMatch.tap();XCTAssertTrue(app.staticTexts["Nights"].firstMatch.waitForExistence(timeout:5))
        app.buttons["Close search"].tap()
        app.buttons["Collection options"].tap();app.buttons["Playlists"].tap()
        let newList=app.textFields["New personal collection"];XCTAssertTrue(newList.waitForExistence(timeout:5))
        newList.tap();newList.typeText("Gesture Notes");app.buttons["Create collection"].tap()
        app.staticTexts["Gesture Notes"].tap();app.buttons["Collection actions"].tap();app.buttons["Add records"].tap()
        app.buttons["Nights"].firstMatch.tap();app.buttons["Done"].firstMatch.tap();capture("07b-Playlist")
        app.navigationBars.buttons["Playlists"].tap();app.buttons["Done"].firstMatch.tap()
        app.buttons["Collection options"].tap();app.buttons["Settings & backup"].tap()
        let lighting=app.switches["Artwork lighting"];XCTAssertTrue(lighting.waitForExistence(timeout:5))
        lighting.tap();let savedLighting=lighting.value as? String;capture("07c-Settings")
        app.buttons["Done"].firstMatch.tap()
        app.terminate();app.launch()
        XCTAssertTrue(app.buttons["focused-album"].waitForExistence(timeout:15));capture("08-Persisted-relaunch")
        app.buttons["Collection options"].tap();app.buttons["Settings & backup"].tap()
        XCTAssertTrue(lighting.waitForExistence(timeout:5));XCTAssertEqual(lighting.value as? String,savedLighting)
    }
    @MainActor func testAlbumFocusPerformance() {
        let app=XCUIApplication();app.launchArguments=["--ui-fixtures"];app.launch()
        XCTAssertTrue(app.buttons["Next album"].waitForExistence(timeout:30))
        let options=XCTMeasureOptions();options.iterationCount=3
        measure(metrics:[XCTClockMetric(),XCTMemoryMetric(application:app),XCTOSSignpostMetric(subsystem:"personal.digitalanalog",category:"Navigation",name:"AlbumFocus")],options:options) {
            app.buttons["Next album"].tap()
        }
    }
    @MainActor private func capture(_ name:String) { let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a) }
}
