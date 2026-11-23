import XCTest

final class Journey: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.openui.openui")

    func checkpoint(_ line: String) { print("FOURIER_UI " + line) }

    func match(_ text: String, in root: XCUIElement, prefix: Bool = false) -> XCUIElement? {
        let filter = NSPredicate(format: prefix ? "label BEGINSWITH[c] %@" : "label ==[c] %@", text)
        for type in [XCUIElement.ElementType.button, .link, .cell, .staticText] {
            let candidates = root.descendants(matching: type).matching(filter).allElementsBoundByIndex
            if let target = candidates.first(where: { $0.exists && $0.isHittable }) { return target }
        }
        return nil
    }

    func until(_ seconds: Int = 15, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(Double(seconds))
        repeat { if condition() { return true }; Thread.sleep(forTimeInterval: 0.45) } while Date() < end
        return false
    }

    func tap(_ t: String, prefix: Bool = false, scroll: Bool = false) throws {
        for i in 0..<(scroll ? 7 : 3) {
            if let e = match(t, in: app, prefix: prefix) { e.tap(); return }
            if scroll && i > 0 { app.swipeUp() } else { Thread.sleep(forTimeInterval: 0.7) }
        }
        XCTFail("Could not see UI control: " + t + " . Visible = " + labels())
        throw NSError(domain: "VisibleUI", code: 1)
    }

    func labels() -> String {
        // Public UI labels only. Never log text field contents, the keyboard, or credentials.
        let labels = (app.buttons.allElementsBoundByIndex + app.staticTexts.allElementsBoundByIndex)
            .filter { $0.exists && $0.isHittable }.prefix(50).map { $0.label }
        return labels.joined(separator: " | ")
    }

    func openVoice() throws {
        if !until(3, { self.match("Server Settings", in: self.app) != nil }) {
            if let menu = match("Menu", in: app) { menu.tap() }
            else { app.swipeRight() }
        }
        if !until(6, { self.match("Server Settings", in: self.app) != nil }) { app.swipeRight() }
        try tap("Server Settings"); try tap("Voice",prefix:true,scroll:true)
        try tap("Your Voice",prefix:true,scroll:true)
    }

    func dismissInitialScreens() {
        for _ in 0..<8 {
            var pressed = false
            for label in ["Not Now","Skip","Get started","Continue"] {
                if let e = match(label,in:app) { e.tap(); pressed = true; break }
            }
            if !pressed && (match("Menu",in:app) != nil || match("Server Settings",in:app) != nil) { break }
            Thread.sleep(forTimeInterval:0.5)
        }
    }

    func testServerLoginAndFourierSelection() throws {
        continueAfterFailure = false; app.launch()
        let url = app.textFields.firstMatch
        XCTAssertTrue(url.waitForExistence(timeout:22), labels()); url.tap()
        url.typeText("http://127.0.0.1:8319\n")
        if !until(7, { self.match("Email & Password",in:self.app,prefix:true) != nil }) { try tap("Connect",scroll:true) }
        XCTAssertTrue(until(18, { self.match("Email & Password",in:self.app,prefix:true) != nil }), labels())
        checkpoint("Production server connection accepted stock Open WebUI on loopback")
        try tap("Email & Password",prefix:true)
        let email = app.textFields.firstMatch, pass=app.secureTextFields.firstMatch
        XCTAssertTrue(email.waitForExistence(timeout:10)); email.tap(); email.typeText("fourier-qa@example.test")
        XCTAssertTrue(pass.exists);pass.tap();pass.typeText("QA_PASS_PHRASE\n")
        if !until(8, { self.match("Not Now",in:self.app) != nil || self.match("Skip",in:self.app) != nil || self.match("Menu",in:self.app) != nil }) {
            if match("Sign in",in:app) != nil { try tap("Sign in") }
        }
        dismissInitialScreens()
        try openVoice()
        checkpoint("Authenticated original SwiftUI: Settings / Voice / Your Voice")
        try tap("Recognition model",prefix:true,scroll:true)
        try tap("Oruk Fourier 2B",prefix:true)
        XCTAssertTrue(until(8,{ self.match("English · 2.48 GB · Model license",in:self.app,prefix:true) != nil }), labels())
        checkpoint("Selected Oruk Fourier 2B in the ordinary model picker; Fourier license row visible")
        let selected = XCTAttachment(screenshot: app.screenshot());selected.name="Fourier-selected";selected.lifetime = .keepAlways;add(selected)
        // Verify persistence before asking the simulator to initialize MLX.
        app.terminate();app.launch();dismissInitialScreens();try openVoice()
        var retained = false
        for _ in 0..<6 {
            if match("English · 2.48 GB · Model license",in:app,prefix:true) != nil { retained=true;break }
            app.swipeUp()
        }
        XCTAssertTrue(retained, "Fourier-specific license row must precede any new selection. " + labels())
        checkpoint("Fourier-specific license row persisted in the original settings after process restart")
        if match("Download & Load Model",in:app) == nil { app.swipeUp() }
        try tap("Download & Load Model",prefix:true,scroll:true)
        checkpoint("Requested Fourier through the normal download button")
        // External test runner collects cache repository name and model files from the app's own sandbox.
        _ = until(180, { self.match("Unload Model",in:self.app,prefix:true) != nil || self.app.state != .runningForeground })
        checkpoint("After download window, app state " + String(describing:app.state))
    }
}
