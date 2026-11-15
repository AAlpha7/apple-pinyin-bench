#!/usr/bin/env bash
# Boot an iPhone simulator with Apple's Pinyin (full keyboard) turned on and the Mac's hardware keyboard not connected,
# so the on-screen keyboard comes up. Prints the simulator's id.
set -euo pipefail
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
d = json.load(sys.stdin)["devices"]
best = None
for rt, devs in d.items():
    if "iOS" not in rt: continue
    for x in devs:
        if x["name"].startswith("iPhone") and "Pro Max" not in x["name"] and (best is None or rt > best[0]):
            best = (rt, x["udid"])
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
