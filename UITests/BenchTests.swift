import XCTest

/// The comparison itself: public sentences typed on Apple's Pinyin keyboard the way a person would, one row at a
/// time, with what Apple's keyboard learnt removed before every row. Nothing is timed by the clock (reading the bar
/// from a screenshot takes seconds): every action is counted, and the speed is worked out afterwards from the counts
/// with one time per kind of action, the same for every keyboard compared.
///
/// A row: text, its pinyin syllables, and where its words end (UITests/Rows.swift).
/// Styles (BENCH_STYLE): `full` = the whole sentence in full pinyin; `wordabbr` = one word at a time as initials, and
/// a word not offered that way typed again in full pinyin.
/// What the person does: after the keys, looks at the bar (the candidates readable without scrolling); takes the
/// longest candidate that starts what is still to be written (the first one with space, another with a tap); if none
/// does, deletes the keys and types the next character alone in full pinyin (wordabbr: first the word in full); a
/// character still not offered is given up (counted, left out of the field). With nothing typed and something
/// written, a predicted word that starts what is left is taken with a tap.
/// One line a row: ROW|style|number|text|field|keys|spaces|taps (bar index of each)|deletes|clears|given up|looks|
/// wholes (first / on the bar / tries)|ok. BENCH_FROM / BENCH_COUNT pick the rows.
final class BenchTests: XCTestCase {
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

    struct Counts {
        var keys = 0, spaces = 0, taps: [Int] = [], deletes = 0, clears = 0, givenUp = 0, looks = 0
        var wholeTries = 0, wholeFirst = 0, wholeOnBar = 0
    }

    static func letters(_ s: String) -> Int { s.unicodeScalars.filter { (97...122).contains($0.value) }.count }

    /// One row. Returns the counts, what the field holds at the end, and whether every pick put in what was read.
    func typeRow(text: String, syl: [String], wordEnds: [Int], byWord: Bool) -> (Counts, String, Bool) {
        var c = Counts()
        let want = Array(text)
        var done = 0                        // characters of the row dealt with (written or given up)
        var written = ""                    // what the field should hold
        var full = !byWord                  // the keys now typed are full pinyin
        var fresh = false                   // the keys of a whole unit were just typed
        var ok = true
        func unitEnd(_ from: Int) -> Int { byWord ? (wordEnds.first { $0 > from } ?? want.count) : want.count }
        func keysFor(_ from: Int, full: Bool) -> String { syl[from..<unitEnd(from)].map { full ? $0 : String($0.prefix(1)) }.joined() }
        func composing() -> Bool { Self.letters(b.value) > 0 }
        func typeKeys(_ k: String) { b.type(k); c.keys += k.count }
        func clearKeys() {
            var n = 0
            while composing(), n < 80 { b.delete(1); n += 1 }
            c.deletes += n; c.clears += 1
        }
        /// the longest candidate on the bar that starts what is left; taken. False when there is none.
        func pick(wasComposing: Bool) -> Bool {
            let rest = String(want[done...])
            let bar = b.bar()
            c.looks += 1
            if wasComposing, fresh {
                fresh = false
                let whole = String(want[done..<unitEnd(done)])
                if bar.first?.text == whole { c.wholeFirst += 1 }
                if bar.contains(where: { $0.text == whole }) { c.wholeOnBar += 1 }
            }
            var best: Int?
            for (i, x) in bar.enumerated() where !x.text.isEmpty && rest.hasPrefix(x.text) {
                if best == nil || x.text.count > bar[best!].text.count { best = i }
            }
            guard let k = best else { return false }
            if wasComposing, k == 0 { b.space(); c.spaces += 1 } else { b.tap(bar[k]); c.taps.append(k) }
            usleep(300_000)
            written += bar[k].text
            done += bar[k].text.count
            if Board.han(b.value) != written {      // the bar was misread, or the keyboard put in something else
                print("MISPICK|\(text)|read=\(bar[k].text)|field=\(Board.han(b.value))|expected=\(written)")
                ok = false
            }
            return true
        }
        var steps = 0
        while done < want.count, ok {
            steps += 1
            if steps > 4 * want.count + 20 { ok = false; break }
            if !composing() {
                if done > 0, pick(wasComposing: false) { continue }
                full = !byWord
                c.wholeTries += 1; fresh = true
                typeKeys(keysFor(done, full: full))
                continue
            }
            if pick(wasComposing: true) { continue }
            clearKeys()
            if byWord, !full {
                full = true
                c.wholeTries += 1; fresh = true
                typeKeys(keysFor(done, full: true))
                continue
            }
            fresh = false
            typeKeys(syl[done])
            if composing(), pick(wasComposing: true) {
                if composing() { clearKeys() }
                continue
            }
            if composing() { clearKeys() }
            c.givenUp += 1; done += 1
        }
        if composing() { clearKeys() }
        return (c, Board.han(b.value), ok)
    }

    func testBench() throws {
        let env = ProcessInfo.processInfo.environment
        let style = env["BENCH_STYLE"] ?? "full"
        let from = Int(env["BENCH_FROM"] ?? "") ?? 0
        let count = Int(env["BENCH_COUNT"] ?? "") ?? benchRows.count
        XCTAssertTrue(["full", "wordabbr"].contains(style), "BENCH_STYLE")
        for i in from..<min(benchRows.count, from + count) {
            let r = benchRows[i]
            let reset = b.resetLearning()            // (relaunches the app: an empty field, nothing learnt)
            if !reset { print("RESETFAILED|\(i)") }
            var ends: [Int] = [], e = 0
            for l in r.words { e += l; ends.append(e) }
            let t0 = Date()
            let (c, field, ok) = typeRow(text: r.text, syl: r.syl, wordEnds: ends, byWord: style == "wordabbr")
            print("ROW|\(style)|\(i)|\(r.text)|\(field)|\(c.keys)|\(c.spaces)|\(c.taps.map(String.init).joined(separator: ","))|\(c.deletes)|\(c.clears)|\(c.givenUp)|\(c.looks)|\(c.wholeFirst)/\(c.wholeOnBar)/\(c.wholeTries)|\(ok && reset)|\(Int(Date().timeIntervalSince(t0))) s")
        }
    }
}
