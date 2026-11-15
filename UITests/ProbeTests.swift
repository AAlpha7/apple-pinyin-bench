import XCTest

/// Round 3 of the feasibility probe.
/// 1 OCR (candidates cut from the pixels) against the truth: each candidate of the first screen tapped, what went into the
///   field compared with what was read. 2 Apple learns from a pick; is that undone by Settings' Reset Keyboard
///   Dictionary, or by removing the device's keyboard files (and relaunching)?
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
    func texts(_ keys: String) -> [String] { b.type(keys); let c = b.bar(); b.clearField(); return c.map(\.text) }

    func testProbe() throws {
        // 2a: before anything is picked, the order of a few inputs; then learn (pick a later candidate twice)
        let probes = ["shi", "yixia", "zhongguo"]
        var fresh: [String: [String]] = [:]
        for k in probes { fresh[k] = texts(k); print("LEARN|fresh|\(k)|\(fresh[k]!.joined(separator: " "))") }
        func teach() {
            for k in probes {
                guard let f = fresh[k], f.count > 2 else { continue }
                for _ in 0..<2 { b.type(k); let c = b.bar(); if let x = c.first(where: { $0.text == f[2] }) { b.tap(x) }; usleep(300_000); b.clearField() }
            }
        }
        func check(_ tag: String) {
            for k in probes { let t = texts(k); print("LEARN|\(tag)|\(k)|\(t.joined(separator: " "))|same as fresh=\(t == fresh[k]!)") }
        }
        teach(); check("taught")

        // 2b: Settings
        var t0 = Date()
        let ok = resetDictionary()
        print("RESET|settings|\(ok)|\(Int(Date().timeIntervalSince(t0) * 1000)) ms")
        app.activate(); b.input.tap()
        check("after settings reset")

        // 2c: removing the keyboard files, then the same after relaunching the app
        teach(); check("taught again")
        t0 = Date()
        let dir = ((NSHomeDirectory() as NSString).appendingPathComponent("../../../../Library/Keyboard") as NSString).standardizingPath
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        var removed: [String] = []
        for f in files where f.hasPrefix("zh_Hans") || f.hasPrefix("DynamicPhraseLexicon") || f.hasPrefix("user_model_database") {
            if (try? FileManager.default.removeItem(atPath: dir + "/" + f)) != nil { removed.append(f) }
        }
        print("RESET|files|removed \(removed)|\(Int(Date().timeIntervalSince(t0) * 1000)) ms")
        check("after removing files")
        app.terminate(); app.launch(); b.start()
        check("after removing files + relaunch")

        // 1: OCR against what each tap puts in the field
        var right = 0, wrong = 0
        for keys in ["wzdl", "nihao", "shi", "jintian", "zhongguo", "wmqcfb", "yixia", "dajiahao", "yi", "ji", "zhi", "li", "ta", "women", "xianzai", "ok"] where keys != "ok" {
            b.type(keys)
            let first = b.bar()
            line("BAR", keys, first)
            for (k, c) in first.enumerated() {
                if k > 0 { b.type(keys); let again = b.bar(); if again.map(\.text) != first.map(\.text) { line("BARCHANGED", keys, again) } }
                b.tap(c)
                usleep(300_000)
                let got = Board.han(b.value)
                let ok = got == c.text
                if ok { right += 1 } else { wrong += 1 }
                print("TAP|\(keys)|\(k)|read=\(c.text)|field=\(got)|\(ok)")
                b.clearField()
            }
        }
        print("OCRCHECK|right=\(right)|wrong=\(wrong)")
        // 联想 after a pick
        b.type("nihao"); if let c = b.bar().first { b.tap(c) }
        usleep(500_000)
        line("PREDICT", "after 你好", b.bar())
        b.clearField()
    }

    /// Settings > General > Transfer or Reset iPhone > Reset > Reset Keyboard Dictionary
    func resetDictionary() -> Bool {
        let s = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        s.terminate(); s.launch()
        func find(_ labels: [String], scroll: Bool = false) -> XCUIElement? {
            for attempt in 0..<(scroll ? 6 : 1) {
                for l in labels { for q in [s.cells[l], s.buttons[l], s.staticTexts[l]] where q.waitForExistence(timeout: attempt == 0 ? 3 : 1) && q.isHittable { return q } }
                if scroll { s.swipeUp() }
            }
            print("RESET|missing \(labels)|on screen: " + s.descendants(matching: .any).allElementsBoundByIndex.prefix(80).map { $0.label }.filter { !$0.isEmpty }.joined(separator: " / "))
            return nil
        }
        guard let g = find(["General", "通用"]) else { return false }; g.tap()
        guard let t = find(["Transfer or Reset iPhone", "传输或还原 iPhone"], scroll: true) else { return false }; t.tap()
        guard let r = find(["Reset", "还原"]) else { return false }; r.tap()
        guard let k = find(["Reset Keyboard Dictionary", "还原键盘字典"]) else { return false }; k.tap()
        usleep(500_000)
        for e in s.descendants(matching: .any).allElementsBoundByIndex where e.elementType == .button { print("RESET|button|\(e.label)") }
        let confirm = s.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Reset Dictionary' OR label CONTAINS '还原字典'")).firstMatch
        if confirm.waitForExistence(timeout: 3) { confirm.tap(); usleep(1_000_000); return true }
        return false
    }
}
