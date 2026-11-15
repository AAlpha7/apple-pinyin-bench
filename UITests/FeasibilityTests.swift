import XCTest
import Vision

/// Stage 1: can Apple Pinyin be driven key by key, and can its candidates be read and tapped from a UI test?
/// Prints lines the workflow log keeps:
///   KEYBOARD|<n>|<what the space key and a few keys are labelled>   one per keyboard the globe key cycles through
///   FIELD|<pinyin>|<the text box while composing>
///   OCR|<pinyin>|<text read from the screen above the keys>|<x,y,w,h points>|<confidence>
///   PICK|<pinyin>|<candidate tapped>|<text box afterwards>|<ok>
///   LAT|<pinyin>|<ms from the last key tap until Chinese text is read above the keys>
final class FeasibilityTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        // the keyboards for this app's process too (argument domain), in case the device preference is not read
        app.launchArguments += ["-AppleKeyboards", "(\"zh_Hans-Pinyin@sw=Pinyin-Simplified;hw=Automatic\")",
                                "-AppleKeyboardsExpanded", "1"]
        app.launch()
    }

    func testDriveApplePinyin() throws {
        let input = app.textFields["input"].exists ? app.textFields["input"] : app.textViews["input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10), "text box")
        input.tap()
        let kb = app.keyboards.firstMatch
        XCTAssertTrue(kb.waitForExistence(timeout: 10), "a software keyboard came up (hardware keyboard must be off)")

        // Apple Pinyin is reached when typing letters brings up Chinese candidates; otherwise try the globe key
        // (on iPhones without a home button it sits below the keyboard, so it is looked for in the whole app too)
        var found = false
        for n in 0..<6 {
            let labels = kb.descendants(matching: .any).allElementsBoundByIndex.map { $0.label }.filter { !$0.isEmpty }
            print("KEYBOARD|\(n)|\(labels.prefix(40).joined(separator: " "))")
            if kb.keys["n"].exists, kb.keys["i"].exists {
                kb.keys["n"].tap(); kb.keys["i"].tap()
                let t0 = Date()
                let top = kb.keys["q"].frame.minY
                while Date().timeIntervalSince(t0) < 5, !found {
                    found = ocr(XCUIScreen.main.screenshot().image).contains { $0.rect.maxY <= top + 2 && isCJK($0.text) }
                }
                print("KEYBOARD|\(n)|typed ni, Chinese candidates: \(found)")
                for _ in 0..<2 { if kb.keys["delete"].exists { kb.keys["delete"].tap() } else if kb.buttons["delete"].exists { kb.buttons["delete"].tap() } }
                app.buttons["clear"].tap(); input.tap()
                if found { break }
            }
            let names = ["Next keyboard", "下一个键盘", "Next Keyboard"]
            let globe = names.lazy.map { self.app.buttons[$0] }.first { $0.exists }
            for b in app.buttons.allElementsBoundByIndex where !b.label.isEmpty { print("BUTTON|\(b.label)|\(b.identifier)") }
            guard let g = globe else { print("KEYBOARD|no globe key"); break }
            g.tap()
            sleep(1)
        }
        XCTAssertTrue(found, "Apple Pinyin candidates seen (the rest still runs, for the log)")

        // run 4: the candidate bar is not in the accessibility tree (only the keys are), so it is read from a
        // screenshot with Vision's text recognition, and tapped by position
        let keysTop = kb.keys["q"].frame.minY
        let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for (pinyin, want) in [("nihao", "你好"), ("wozhidaole", "我知道了"), ("wzdl", "我知道了"), ("jintiantianqi", "今天天气")] {
            for ch in pinyin {
                let key = kb.keys[String(ch)]
                XCTAssertTrue(key.exists, "key \(ch)")
                key.tap()
            }
            print("FIELD|\(pinyin)|value=\((input.value as? String) ?? "-")|placeholder=\(input.placeholderValue ?? "-")|keyboard top \(Int(keysTop)) frame \(kb.frame)")
            // everything Vision reads anywhere on the screen, top to bottom (where is the composition, if anywhere?)
            for b in ocr(XCUIScreen.main.screenshot().image).sorted(by: { $0.rect.minY < $1.rect.minY }) {
                print("SCREEN|\(pinyin)|\(b.text)|\(Int(b.rect.minX)),\(Int(b.rect.minY)),\(Int(b.rect.width)),\(Int(b.rect.height))|\(String(format: "%.2f", b.conf))")
            }
            if pinyin == "nihao" {
                for line in app.debugDescription.split(separator: "\n") where !line.contains("Padding") { print("TREE|\(line)") }
            }
            for e in sb.descendants(matching: .any).allElementsBoundByIndex where isCJK(e.label) {
                print("SPRINGBOARD|\(e.elementType.rawValue)|\(e.label)")
            }
            let t0 = Date()
            var boxes: [(text: String, rect: CGRect, conf: Float)] = []
            while Date().timeIntervalSince(t0) < 5 {
                boxes = ocr(XCUIScreen.main.screenshot().image).filter { $0.rect.maxY <= keysTop + 2 && isCJK($0.text) }
                if !boxes.isEmpty { break }
            }
            print("LAT|\(pinyin)|\(Int(Date().timeIntervalSince(t0) * 1000)) ms until text above the keys (includes screenshot + OCR time)")
            for b in boxes { print("OCR|\(pinyin)|\(b.text)|\(Int(b.rect.minX)),\(Int(b.rect.minY)),\(Int(b.rect.width)),\(Int(b.rect.height))|\(String(format: "%.2f", b.conf))") }
            let attach = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attach.name = pinyin; attach.lifetime = .keepAlways; add(attach)
            // the field also shows the composing pinyin; candidates are the boxes in the bar just above the keys
            let bar = boxes.filter { $0.rect.minY > keysTop - 80 }
            if let c = bar.first(where: { $0.text.hasPrefix(want) }) ?? bar.first {
                app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: c.rect.midX, dy: c.rect.midY)).tap()
                sleep(1)
                let value = (input.value as? String) ?? ""
                print("PICK|\(pinyin)|\(c.text)|\(value)|\(value.contains(want))")
            } else {
                print("PICK|\(pinyin)|-|-|false")
            }
            app.buttons["clear"].tap()
            input.tap()
        }
    }

    /// Chinese text on the screen with its box in points (Vision's boxes are normalised, origin bottom left)
    func ocr(_ image: UIImage) -> [(text: String, rect: CGRect, conf: Float)] {
        guard let cg = image.cgImage else { return [] }
        let req = VNRecognizeTextRequest()
        req.recognitionLanguages = ["zh-Hans", "en-US"]
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: cg).perform([req])
        let size = app.frame.size
        return (req.results ?? []).compactMap { o in
            guard let top = o.topCandidates(1).first else { return nil }
            let b = o.boundingBox
            let r = CGRect(x: b.minX * size.width, y: (1 - b.maxY) * size.height, width: b.width * size.width, height: b.height * size.height)
            return (top.string, r, top.confidence)
        }
    }

    func isCJK(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
            && !["空格", "删除", "数字", "换行", "确认", "拼音", "下一个键盘"].contains(s.trimmingCharacters(in: .whitespaces))
    }
}
