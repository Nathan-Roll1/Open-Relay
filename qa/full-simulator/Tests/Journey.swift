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
        continueAfterFailure = false
        // Independent in-simulator control uses the same loopback route as the real app.
        let health = expectation(description: "iOS simulator can reach the stock server")
        var request = URLRequest(url: URL(string:"http://127.0.0.1:8320/health")!)
        request.setValue("simulator", forHTTPHeaderField:"X-Fourier-Diagnostic")
        URLSession.shared.dataTask(with:request) { _, response, error in
            // The UI test carrier and the product have separate transport policies.
            // Keep the independent probe's result without gating the real app.
            print("FOURIER_UI Simulator preflight HTTP", (response as? HTTPURLResponse)?.statusCode ?? 0, "URL error", (error as NSError?)?.code ?? 0)
            health.fulfill()
        }.resume()
        wait(for:[health],timeout:15)
        let host = "http://127.0.0.1:8320"
        app.launch()
        let url = app.textFields.firstMatch
        XCTAssertTrue(url.waitForExistence(timeout:22), labels()); url.tap()
        url.typeText(host)
        XCTAssertEqual(url.value as? String, host)
        let scroll=app.scrollViews.firstMatch
        XCTAssertTrue(scroll.exists, "The server form scroll view must be visible")
        func capture(_ stage:String) {
            // Called only on the server form, before a password is entered.
            let tmp = FileManager.default.temporaryDirectory
            try? app.screenshot().pngRepresentation.write(to:tmp.appendingPathComponent("fourier-public-"+stage+".png"))
            let controls = scroll.buttons.allElementsBoundByIndex.map { b in
                [b.label, b.identifier, String(describing:b.frame), String(b.isEnabled), String(b.isHittable)].joined(separator:" | ")
            }
            try? controls.joined(separator:"\n").write(to:tmp.appendingPathComponent("fourier-public-controls.txt"),atomically:true,encoding:.utf8)
            checkpoint("Form controls "+stage+": "+controls.joined(separator:" / "))
        }
        func connectionControl() -> XCUIElement? {
            let keyboard = app.keyboards.firstMatch
            let bottom = keyboard.exists ? keyboard.frame.minY : app.frame.maxY
            let controls = scroll.buttons.allElementsBoundByIndex.filter { b in
                b.exists && b.isEnabled && b.isHittable && b.frame.midY < bottom &&
                    b.frame.width > app.frame.width*0.45 && b.frame.height >= 38
            }
            if let connect = controls.first(where: { $0.label.localizedCaseInsensitiveContains("Connect") }) {
                return connect
            }
            guard let advanced = match("Advanced",in:scroll,prefix:true) else {return nil}
            let candidates=controls.filter { $0.label.isEmpty && $0.frame.midY > advanced.frame.maxY }
            return candidates.count == 1 ? candidates[0] : nil
        }
        var action=connectionControl()
        // Scroll the form above the keyboard; never select a key from the keyboard itself.
        for _ in 0..<4 where action == nil {
            let kb=app.keyboards.firstMatch
            let bottom=kb.exists ? kb.frame.minY : scroll.frame.maxY
            let start=CGVector(dx:0.82,dy:min(0.85,(bottom-30-scroll.frame.minY)/scroll.frame.height))
            scroll.coordinate(withNormalizedOffset:start).press(forDuration:0.08,thenDragTo:scroll.coordinate(withNormalizedOffset:CGVector(dx:0.82,dy:0.15)))
            action=connectionControl()
        }
        capture("before-connect")
        guard let action=action else { XCTFail("No identifiable, unobstructed connect button in the form"); return }
        checkpoint("Tapping production form action at "+String(describing:action.frame))
        action.tap()
        let authReady = until(65, {
            self.match("Email & Password",in:self.app,prefix:true) != nil ||
              self.match("Choose how you'd like to sign in",in:self.app) != nil ||
              self.app.secureTextFields.firstMatch.exists
        })
        capture("after-connect")
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
