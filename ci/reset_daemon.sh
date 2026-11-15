#!/bin/bash
# Runs on the Mac beside the test. The test runner (a simulator process) can write host files but cannot restart
# the simulator's keyboard service; when it asks (a request file), this removes what Apple's keyboard learnt
# (the device's Library/Keyboard files of the Chinese keyboard and the user model) and restarts the keyboard
# services so they do not keep it in memory, then answers. Only the simulator's own keyboard data is touched.
UDID="$1"
Q=/tmp/applebench
mkdir -p "$Q"; rm -f "$Q"/*
KB="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Library/Keyboard"
first=1
while true; do
  if [ -e "$Q/req" ]; then
    rm -f "$Q/req"
    if [ $first = 1 ]; then
      first=0
      echo "DAEMON|launchd labels: $(xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -iE 'kbd|keyboard|textinput|lexicon' | awk '{print $3}' | tr '\n' ' ')"
    fi
    before=$(ls "$KB" 2>/dev/null | tr '\n' ' ')
    rm -rf "$KB"/zh_Hans* "$KB"/DynamicPhraseLexicon* "$KB"/user_model_database*
    for label in $(xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | awk '{print $3}' | grep -iE '^com\.apple\.(kbd|TextInput|keyboard)'); do
      xcrun simctl spawn "$UDID" launchctl kickstart -k "user/501/$label" >/dev/null 2>&1 \
        || xcrun simctl spawn "$UDID" launchctl kickstart -k "system/$label" >/dev/null 2>&1 \
        || xcrun simctl spawn "$UDID" launchctl stop "$label" >/dev/null 2>&1
      echo "DAEMON|restarted $label"
    done
    echo "DAEMON|reset (files before: $before)"
    touch "$Q/done"
  fi
  sleep 0.2
done
