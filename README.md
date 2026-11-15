# apple-pinyin-bench

Measures Apple's own iOS Pinyin keyboard (the one built into iOS) in the iOS Simulator, on public Chinese sentences,
under a fixed action-time model, so it can be compared with other keyboards measured the same way.

Nothing here is a keyboard. The repo holds only:
- a tiny host app with one text box (`Host/`),
- a UI test that taps Apple Pinyin's keys and reads its candidate bar (`UITests/`),
- the workflow that runs it on a GitHub-hosted macOS runner (`.github/workflows/`).

Stage 1 (this commit): feasibility only. Turn on Apple Pinyin in the simulator, type a few pinyin strings key by key,
print what the candidate bar exposes to the accessibility tree, tap a candidate and check the text box got it.
Public sentence sets and the full measure come only after stage 1 shows the candidates can be read.

Action times used for the measure (seconds): key 0.25; tapping a candidate that is not first 0.25 + 0.15 find
+ 0.05 per candidate before it; one more screen of candidates 0.6; clearing and retyping 0.6.
