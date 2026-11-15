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

    /// The candidate bar: the strip just above the keys, cut from the screenshot at full pixel size and read. Vision
    /// reads a bar as one or a few lines and glues neighbouring candidates together (时事使十), so each character's own
    /// box is taken and a line is cut wherever the gap between two characters is wider than the gap inside a candidate
    /// (characters of one candidate touch; candidates have padding between them). A candidate the bar's right end cuts
    /// off (it reaches the expand button) is not taken: it is not readable yet, as in the comparison's screens.
    /// Read until two reads in a row agree, so a bar still changing after the last key is not taken.
    func bar(wait: TimeInterval = 4) -> [Candidate] {
        let t0 = Date()
        var last: [Candidate]? = nil
        repeat {
            let c = read(top: keysTop - 50, bottom: keysTop - 10)
            if let l = last, !c.isEmpty, l.map(\.text) == c.map(\.text) { return c }
            last = c
            if Date().timeIntervalSince(t0) > wait { return c }
        } while true
    }

    /// x of the bar's right end usable for candidates (the expand button is past it)
    var barRight: CGFloat { app.frame.width - 34 }
    /// gap (points) between two characters above which they belong to different candidates
    static let splitGap: CGFloat = 7

    /// Text read in a band of the screen [top, bottom) (points), split into candidates.
    /// Candidates are found from the pixels, not from Vision's layout (Vision glues neighbouring candidates and its
    /// per-character boxes are estimates): a column of the band holds ink when it has pixels much darker than the
    /// band's background; runs of ink columns closer than `splitGap` belong to one candidate. Each candidate's own
    /// strip is then read by Vision alone.
    func read(top: CGFloat, bottom: CGFloat, cutRight: Bool = true) -> [Candidate] {
        let shot = XCUIScreen.main.screenshot().image
        guard let cg = shot.cgImage else { return [] }
        let size = app.frame.size
        let scale = CGFloat(cg.height) / size.height
        let crop = CGRect(x: 0, y: top * scale, width: CGFloat(cg.width), height: (bottom - top) * scale).integral
        guard let band = cg.cropping(to: crop) else { return [] }
        let w = band.width, h = band.height
        var px = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return [] }
        ctx.draw(band, in: CGRect(x: 0, y: 0, width: w, height: h))
        let bg = Int(px.sorted()[px.count / 2])        // most of the band is background
        let ink = (0..<w).map { x in (0..<h).contains { y in abs(Int(px[y * w + x]) - bg) > 90 } }
        let gap = Int(Board.splitGap * scale)
        var runs: [(Int, Int)] = []
        var x = 0
        while x < w {
            guard ink[x] else { x += 1; continue }
            var e = x
            while e < w {
                var n = e + 1
                while n < w, !ink[n], n - e <= gap { n += 1 }
                if n < w, ink[n], n - e <= gap { e = n } else { break }
            }
            runs.append((x, e))
            x = e + 1
        }
        var out: [Candidate] = []
        for (a, e) in runs {
            let r = CGRect(x: CGFloat(a) / scale, y: top, width: CGFloat(e - a + 1) / scale, height: bottom - top)
            if cutRight, r.maxX >= barRight - 2 { continue }
            let pad = Int(4 * scale)
            let strip = CGRect(x: max(0, a - pad), y: 0, width: min(w, e + pad + 1) - max(0, a - pad), height: h)
            guard let img = band.cropping(to: strip) else { continue }
            let req = VNRecognizeTextRequest()
            req.recognitionLanguages = ["zh-Hans"]
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = false
            try? VNImageRequestHandler(cgImage: img).perform([req])
            let texts = (req.results ?? []).compactMap { $0.topCandidates(1).first }
            let text = Board.han(texts.map(\.string).joined())
            if !text.isEmpty { out.append(Candidate(text: text, rect: r, conf: texts.map(\.confidence).min() ?? 0)) }
        }
        return out
    }

    func tap(_ c: Candidate) {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: c.rect.midX, dy: c.rect.midY)).tap()
    }

    static func hasHan(_ s: String) -> Bool { s.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) } }
    /// Only the Chinese characters of a string (the field shows the composing pinyin as well)
    static func han(_ s: String) -> String { String(s.unicodeScalars.filter { (0x3400...0x9FFF).contains($0.value) }.map(Character.init)) }
}
