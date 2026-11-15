import XCTest

/// Round 2 of the feasibility probe: the parts the full comparison rests on.
/// 1 OCR against the truth: tap each candidate of the first screen and compare what went into the field with what was read.
/// 2 the space key takes the first candidate; 3 the next screens (swipe the bar, or the expand button); 4 what shows after
///   a pick with nothing typed (联想); 5 does Apple learn from a pick, and does Settings' Reset Keyboard Dictionary undo it.
final class ProbeTests: XCTestCase {
    var app: XCUIApplication!
    var b: Board!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-AppleKeyboards", "(\"zh_Hans-Pinyin@sw=Pinyin-Simplified;hw=Automatic\")", "-AppleKeyboardsExpanded", "1"]
        app.launch()
        b = Board(app: app)
        b.start()
    }

    func line(_ tag: String, _ key: String, _ cs: [Candidate]) {
        print("\(tag)|\(key)|" + cs.map { "\($0.text)@\(Int($0.rect.minX))-\(Int($0.rect.maxX))" }.joined(separator: " "))
    }

    func testProbe() throws {
        // 1 + 2: OCR against what each tap puts in the field
        var right = 0, wrong = 0
        for keys in ["wzdl", "nihao", "shi", "jintian", "zhongguo", "wmqcfb", "yixia", "dajiahao"] {
            b.type(keys)
            let first = b.bar()
            line("BAR", keys, first)
            for (k, c) in first.enumerated() {
                if k > 0 { b.type(keys); _ = b.bar() }
                b.tap(c)
                usleep(300_000)
                let got = Board.han(b.value)
                let ok = got == Board.han(c.text)
                if ok { right += 1 } else { wrong += 1 }
                print("TAP|\(keys)|\(k)|read=\(c.text)|field=\(got)|\(ok)")
                b.clearField()
            }
            b.type(keys); _ = b.bar()
            b.space(); usleep(300_000)
            print("SPACE|\(keys)|first read=\(first.first?.text ?? "-")|field=\(Board.han(b.value))")
            b.clearField()
        }
        print("OCRCHECK|right=\(right)|wrong=\(wrong)")

        // 3: the next screens
        b.type("shi")
        let s1 = b.bar()
        line("SCREEN1", "shi", s1)
        let barY = (s1.first?.rect.midY ?? b.keysTop - 25)
        let from = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 300, dy: barY))
        let to = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 40, dy: barY))
        from.press(forDuration: 0.05, thenDragTo: to)
        usleep(500_000)
        line("SCREEN2", "shi", b.bar())
        for e in b.kb.descendants(matching: .any).allElementsBoundByIndex where e.frame.minY < b.keysTop && !e.label.isEmpty {
            print("ABOVEKEYS|\(e.elementType.rawValue)|\(e.label)|\(e.frame)")
        }
        // expand button: right end of the bar
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width - 20, dy: barY)).tap()
        usleep(700_000)
        for y in stride(from: b.keysTop - 52, to: app.frame.height - 40, by: 48) {
            line("GRID", "shi y\(Int(y))", b.read(top: y, bottom: y + 48))
        }
        b.clearField()

        // 4: 联想 after a pick
        b.type("nihao"); let n = b.bar(); if let c = n.first { b.tap(c) }
        usleep(500_000)
        line("PREDICT", "after 你好", b.read(top: b.keysTop - 52, bottom: b.keysTop - 2))
        b.clearField()

        // 5: learning
        b.type("shi"); let before = b.bar(); line("LEARN", "before", before)
        if before.count > 3 { b.tap(before[3]); print("LEARN|picked|\(before[3].text)") }
        b.clearField()
        b.type("shi"); line("LEARN", "after one pick", b.bar()); b.clearField()
        if before.count > 3 { for _ in 0..<2 { b.type("shi"); let c = b.bar(); if let x = c.first(where: { $0.text == before[3].text }) { b.tap(x) }; b.clearField() } }
        b.type("shi"); line("LEARN", "after three picks", b.bar()); b.clearField()
        // a sentence typed twice: is the first candidate the same?
        for i in 0..<2 { b.type("wmqcfb"); let c = b.bar(); line("TWICE", "\(i)", c); if c.count > 1 { b.tap(c[1]) }; b.clearField() }
        b.type("wmqcfb"); line("TWICE", "after picking the 2nd twice", b.bar()); b.clearField()

        // reset through Settings
        let t0 = Date()
        let ok = resetDictionary()
        print("RESET|\(ok)|\(Int(Date().timeIntervalSince(t0) * 1000)) ms")
        app.activate(); b.input.tap()
        b.type("shi"); line("LEARN", "after reset", b.bar()); b.clearField()
        b.type("wmqcfb"); line("TWICE", "after reset", b.bar()); b.clearField()

        // the device's keyboard data, seen from the test runner (could a reset be done by removing files?)
        let home = NSHomeDirectory()
        print("FILES|home \(home)")
        for p in ["/../../../../Library/Keyboard", "/../../../../../Library/Keyboard"] {
            let d = (home + p as NSString).standardizingPath
            print("FILES|\(d)|\((try? FileManager.default.contentsOfDirectory(atPath: d)) ?? ["(cannot list)"])")
        }
    }

    /// Settings > General > Transfer or Reset iPhone > Reset > Reset Keyboard Dictionary
    func resetDictionary() -> Bool {
        let s = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        s.terminate(); s.launch()
        func go(_ labels: [String]) -> Bool {
            for l in labels {
                for q in [s.cells[l], s.buttons[l], s.staticTexts[l]] where q.waitForExistence(timeout: 3) { q.tap(); return true }
            }
            print("RESET|missing \(labels)|on screen: " + s.descendants(matching: .any).allElementsBoundByIndex.prefix(60).map { $0.label }.filter { !$0.isEmpty }.joined(separator: " / "))
            return false
        }
        guard go(["General", "通用"]) else { return false }
        s.swipeUp()
        guard go(["Transfer or Reset iPhone", "传输或还原 iPhone"]) else { return false }
        guard go(["Reset", "还原"]) else { return false }
        guard go(["Reset Keyboard Dictionary", "还原键盘字典"]) else { return false }
        usleep(500_000)
        let confirm = s.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Reset Dictionary' OR label CONTAINS '还原字典'")).firstMatch
        if confirm.waitForExistence(timeout: 3) { confirm.tap(); return true }
        print("RESET|no confirm|" + s.buttons.allElementsBoundByIndex.map { $0.label }.joined(separator: " / "))
        return false
    }
}
