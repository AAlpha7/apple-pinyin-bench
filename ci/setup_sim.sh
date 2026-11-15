#!/usr/bin/env bash
# Boot an iPhone simulator with Apple's Pinyin (full keyboard) turned on and the Mac's hardware keyboard not connected,
# so the on-screen keyboard comes up. Prints the simulator's id.
set -euo pipefail
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false
# the newest iOS runtime this Xcode's simulator SDK can run (a newer runtime needs a newer Xcode)
SDK=$(xcrun --sdk iphonesimulator --show-sdk-version)
UDID=$(xcrun simctl list devices available -j | SDK="$SDK" python3 -c '
import json, os, re, sys
sdk = tuple(int(x) for x in os.environ["SDK"].split("."))
d = json.load(sys.stdin)["devices"]
best = None
for rt, devs in d.items():
    m = re.search(r"iOS-(\d+)-(\d+)", rt)
    if not m: continue
    v = (int(m.group(1)), int(m.group(2)))
    if v > sdk[:2]: continue
    for x in devs:
        if x["name"].startswith("iPhone") and "Pro Max" not in x["name"] and (best is None or v > best[0]):
            best = (v, x["udid"], x["name"])
if best is None: sys.exit("no iPhone simulator for SDK %s" % os.environ["SDK"])
print("simulator: %s iOS %d.%d" % (best[2], *best[0]), file=sys.stderr)
print(best[1])')
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl spawn "$UDID" defaults write -g AppleKeyboards -array \
  "en_US@sw=QWERTY;hw=Automatic" "zh_Hans-Pinyin@sw=Pinyin-Simplified;hw=Automatic"
xcrun simctl spawn "$UDID" defaults write -g AppleKeyboardsExpanded -int 1
xcrun simctl spawn "$UDID" defaults write com.apple.Preferences KeyboardAutocorrection -bool false
xcrun simctl spawn "$UDID" launchctl stop com.apple.SpringBoard 2>/dev/null || true
sleep 5
xcrun simctl bootstatus "$UDID" -b >/dev/null
echo "$UDID"
