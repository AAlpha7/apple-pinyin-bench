import XCTest

/// Stage 1: can Apple Pinyin be driven key by key, and can its candidates be read and tapped from a UI test?
/// Prints lines the workflow log keeps:
///   KEYBOARD|<n>|<what the space key and a few keys are labelled>   one per keyboard the globe key cycles through
///   NODE|<type>|<label>|<identifier>|<x,y,w,h>                       every element under the keyboard after typing
///   PICK|<pinyin>|<candidate tapped>|<text box afterwards>|<ok>
///   LAT|<pinyin>|<ms from the last key tap until the candidate bar shows a CJK label>
final class FeasibilityTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()
    }

    func testDriveApplePinyin() throws {
        let input = app.textFields["input"].exists ? app.textFields["input"] : app.textViews["input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "text box")
        input.tap()
        let kb = app.keyboards.firstMatch
        XCTAssertTrue(kb.waitForExistence(timeout: 10), "a software keyboard came up (hardware keyboard must be off)")

        // cycle the globe key until a keyboard shows Chinese labels (Apple Pinyin labels its space key in Chinese)
        var found = false
        for n in 0..<6 {
            let labels = kb.descendants(matching: .any).allElementsBoundByIndex.map { $0.label }.filter { !$0.isEmpty }
            print("KEYBOARD|\(n)|\(labels.prefix(40).joined(separator: " "))")
            if labels.contains(where: { $0.contains("空格") || $0.contains("拼音") }) { found = true; break }
            let globe = kb.buttons["Next keyboard"].exists ? kb.buttons["Next keyboard"] : kb.buttons["下一个键盘"]
            guard globe.exists else { print("KEYBOARD|no globe key"); break }
            globe.tap()
            sleep(1)
        }
        XCTAssertTrue(found, "Apple Pinyin keyboard reached")
        guard found else { return }

        for (pinyin, want) in [("nihao", "你好"), ("wozhidaole", "我知道了"), ("wzdl", "我知道了"), ("jintiantianqi", "今天天气")] {
            for ch in pinyin {
                let key = kb.keys[String(ch)]
                XCTAssertTrue(key.exists, "key \(ch)")
                key.tap()
            }
            let t0 = Date()
            var cjk: [XCUIElement] = []
            while Date().timeIntervalSince(t0) < 5 {
                cjk = kb.descendants(matching: .any).allElementsBoundByIndex.filter { isCJK($0.label) }
                if !cjk.isEmpty { break }
            }
            print("LAT|\(pinyin)|\(Int(Date().timeIntervalSince(t0) * 1000))")
            for e in kb.descendants(matching: .any).allElementsBoundByIndex where !e.label.isEmpty || !e.identifier.isEmpty {
                let f = e.frame
                print("NODE|\(e.elementType.rawValue)|\(e.label)|\(e.identifier)|\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width)),\(Int(f.height))")
            }
            // also outside the keyboard element, in case the candidate bar is a sibling of it
            for e in app.descendants(matching: .any).allElementsBoundByIndex where isCJK(e.label) && !cjk.contains(e) {
                let f = e.frame
                print("NODE_OUTSIDE|\(e.elementType.rawValue)|\(e.label)|\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width)),\(Int(f.height))")
            }
            let attach = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attach.name = pinyin; attach.lifetime = .keepAlways; add(attach)
            if let c = cjk.first(where: { $0.label == want }) ?? cjk.first {
                let picked = c.label
                c.tap()
                sleep(1)
                let value = (input.value as? String) ?? ""
                print("PICK|\(pinyin)|\(picked)|\(value)|\(value.hasSuffix(picked))")
            } else {
                print("PICK|\(pinyin)|-|-|false")
            }
            app.buttons["clear"].tap()
            input.tap()
        }
    }

    func isCJK(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) } && !s.contains("空格")
    }
}
