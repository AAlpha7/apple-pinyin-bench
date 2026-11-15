import XCTest
import Vision

/// What a person sees and touches on Apple's Pinyin keyboard, for the bench: keys by accessibility, the candidate
/// bar (not in the accessibility tree) by reading a screenshot with Vision, candidates tapped by position.
struct Candidate { var text: String; var rect: CGRect; var conf: Float }

final class Board {
    let app: XCUIApplication
    let input: XCUIElement
    var kb: XCUIElement { app.keyboards.firstMatch }
    var keysTop: CGFloat = 0
    init(app: XCUIApplication) {
        self.app = app
        input = app.textFields["input"]
    }

    func start() {
        XCTAssertTrue(input.waitForExistence(timeout: 10), "text box")
        input.tap()
        XCTAssertTrue(kb.waitForExistence(timeout: 10), "software keyboard")
        // a fresh simulator puts the slide-to-type introduction over the keys (setup_sim.sh marks it shown; fallback)
        for place: XCUIApplication in [app, XCUIApplication(bundleIdentifier: "com.apple.springboard")] {
            let cont = place.buttons["Continue"]
            if cont.waitForExistence(timeout: 2) { print("INTRO|dismissed"); cont.tap() }
        }
        keysTop = kb.keys["q"].frame.minY
    }

    func type(_ keys: String) {
        for ch in keys { kb.keys[String(ch)].tap() }
    }
    /// A key that is not a letter, by any of its names (identifier or label, English or Chinese)
    func named(_ names: [String]) -> XCUIElement {
        for n in names { for q in [kb.keys[n], kb.buttons[n]] where q.exists { return q } }
        XCTFail("no key \(names)"); return kb.keys[names[0]]
    }
    func space() { named(["space", "空格"]).tap() }
    func delete(_ n: Int) { let d = named(["delete", "删除"]); for _ in 0..<n { d.tap() } }
    var value: String { (input.value as? String) ?? "" }
    func clearField() { app.buttons["clear"].tap(); input.tap() }

    /// The candidate bar: the strip just above the keys, cut from the screenshot at full pixel size and read; each
    /// candidate gets its own box (Vision often reads a whole bar as one line with spaces between candidates, so the
    /// line is split at its spaces and each part's own box is taken). Sorted left to right. `wait`: read again until
    /// the bar has Chinese text or the time is up.
    func bar(wait: TimeInterval = 3) -> [Candidate] {
        let t0 = Date()
        repeat {
            let c = read(top: keysTop - 52, bottom: keysTop - 2)
            if !c.isEmpty || Date().timeIntervalSince(t0) > wait { return c }
        } while true
    }

    /// Text read in a band of the screen [top, bottom) (points), split into candidates.
    func read(top: CGFloat, bottom: CGFloat) -> [Candidate] {
        let shot = XCUIScreen.main.screenshot().image
        guard let cg = shot.cgImage else { return [] }
        let size = app.frame.size
        let scale = CGFloat(cg.height) / size.height
        let crop = CGRect(x: 0, y: top * scale, width: CGFloat(cg.width), height: (bottom - top) * scale).integral
        guard let band = cg.cropping(to: crop) else { return [] }
        let req = VNRecognizeTextRequest()
        req.recognitionLanguages = ["zh-Hans"]
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: band).perform([req])
        var out: [Candidate] = []
        func toPoints(_ b: CGRect) -> CGRect {
            CGRect(x: b.minX * crop.width / scale, y: top + (1 - b.maxY) * crop.height / scale,
                   width: b.width * crop.width / scale, height: b.height * crop.height / scale)
        }
        for o in req.results ?? [] {
            guard let t = o.topCandidates(1).first else { continue }
            let s = t.string
            var i = s.startIndex
            while i < s.endIndex {
                while i < s.endIndex, s[i] == " " { i = s.index(after: i) }
                guard i < s.endIndex else { break }
                var j = i
                while j < s.endIndex, s[j] != " " { j = s.index(after: j) }
                let part = String(s[i..<j])
                if let box = try? t.boundingBox(for: i..<j)?.boundingBox, Board.hasHan(part) {
                    out.append(Candidate(text: part, rect: toPoints(box), conf: t.confidence))
                }
                i = j
            }
        }
        return out.sorted { $0.rect.minX < $1.rect.minX }
    }

    func tap(_ c: Candidate) {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: c.rect.midX, dy: c.rect.midY)).tap()
    }

    static func hasHan(_ s: String) -> Bool { s.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) } }
    /// Only the Chinese characters of a string (the field shows the composing pinyin as well)
    static func han(_ s: String) -> String { String(s.unicodeScalars.filter { (0x3400...0x9FFF).contains($0.value) }.map(Character.init)) }
}
