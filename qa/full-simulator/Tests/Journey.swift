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
        let host = "http://127.0.0.1:8319"
        url.typeText(host)
        XCTAssertEqual(url.value as? String, host, "The ordinary input must contain the expected loopback URL")
        // The form's floating URL label is separate from its text input.
        // Focus the title so the software keyboard does not obscure the form action.
        if let title=match("Open Relay",in:app) { title.tap() }
        func connectionControl() -> XCUIElement? {
            if let labeled=match("Connect",in:app) { return labeled }
            // The app's custom AuthPrimaryButton can expose an empty AX label.
            // Match only the enabled wide action directly below Advanced, above Need help.
            guard let adv = match("Advanced",in:app,prefix:true) else { return nil }
            let help=match("Need help?",in:app)?.frame.minY ?? app.frame.maxY
            let candidate = app.buttons.allElementsBoundByIndex.filter {
                $0.exists && $0.isEnabled && $0.isHittable && $0.label.isEmpty &&
                $0.frame.width > app.frame.width*0.48 && $0.frame.midY >= adv.frame.midY &&
                $0.frame.midY < help && $0.frame.height >= 38
            }
            return candidate.count==1 ? candidate[0] : nil
        }
        var action = connectionControl()
        for _ in 0..<3 where action == nil { app.swipeUp(); action = connectionControl() }
        guard let action = action else {
            let controls=app.buttons.allElementsBoundByIndex.filter{$0.exists}.map{"[\($0.label)] \($0.frame) on=\($0.isEnabled) hittable=\($0.isHittable)"}
            XCTFail("Connection action, exact label or geometry, unavailable: "+controls.joined(separator:"; ")); return
        }
        checkpoint("Tapping original Connect button")
        action.tap()
        let authReady = until(65, {
            self.match("Email & Password",in:self.app,prefix:true) != nil ||
              self.match("Choose how you'd like to sign in",in:self.app) != nil ||
              self.app.secureTextFields.firstMatch.exists
        })
        XCTAssertTrue(authReady, "After real server connection: "+labels())
        if !app.secureTextFields.firstMatch.exists { try tap("Email & Password",prefix:true,scroll:true) }
        let email=app.textFields.firstMatch, pw=app.secureTextFields.firstMatch
        XCTAssertTrue(email.waitForExistence(timeout:8) && pw.exists, "Missing normal login fields: "+labels())
        email.tap(); email.typeText("fourier-qa@example.test"); pw.tap(); pw.typeText("LOCAL_OPEN_WEBUI_PASSWORD")
        checkpoint("Entered a disposable user in the ordinary email/password screen")
        // In the production code the secure field submits the same login method
        // as the Sign in button when the user presses Return.
        pw.typeText("\n")
        func accepted() -> Bool { self.match("Menu",in:self.app) != nil || self.match("Server Settings",in:self.app) != nil || self.match("Skip",in:self.app) != nil || self.match("Not Now",in:self.app) != nil || self.match("Get started",in:self.app) != nil }
        if !until(12,{ accepted() }) {
          if let signin = match("Sign in",in:app) { signin.tap() }
        }
        XCTAssertTrue(until(35,{ accepted() }), "After ordinary password login: "+labels())
        checkpoint("Original app accepted loopback Open WebUI human-session authentication")
        dismissInitialScreens()
        try openVoice()
        checkpoint("Authenticated original SwiftUI: Settings / Voice / Your Voice")
        try tap("Recognition model",prefix:true,scroll:true)
        try tap("Oruk Fourier 2B",prefix:true)
        var visibleLicense=false
        for _ in 0..<5 {
            if match("English · 2.48 GB · Model license",in:app,prefix:true) != nil { visibleLicense=true; break }; app.swipeUp()
        }
        XCTAssertTrue(visibleLicense, labels())
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
