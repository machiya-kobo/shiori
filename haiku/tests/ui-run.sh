#!/bin/bash
# A UI run of Shiori for Haiku, on Haiku: the fake Hister and Kura, the app
# driven with `hey` (Haiku's scripting tool), screenshots, and the fakes'
# log checked for the credential rules. From haiku/ after `make`:
#
#   tests/ui-run.sh [shots-dir]
#
# Replaces ~/config/settings/Shiori/config.json: run it on a test machine.
set -u
cd "$(dirname "$0")/.."
APP=$(ls objects.*/Shiori | head -1)
SHOTS=${1:-/boot/home/mh/shots}
LOG=/boot/home/mh/fake.log
CONFIG=/boot/home/config/settings/Shiori/config.json
mkdir -p "$SHOTS"
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
shot() { sleep "${2:-1}"; hey screen_blanker quit >/dev/null 2>&1 && sleep 1; screenshot -s -f png "$SHOTS/$1.png" >/dev/null 2>&1; }
# Text into a BTextControl: hey's range is [index to length].
settext() { hey Shiori set Text [0 to "${#3}"] of View _input_ of View "$2" of Window "$1" to "$3" >/dev/null; }
cleartext() {
	local n
	n=$(hey Shiori count Text of View _input_ of View "$2" of Window "$1" | grep '"result"' | sed -n 's/.*(B_INT32_TYPE) : \([0-9]*\).*/\1/p')
	[ "${n:-0}" -gt 0 ] && hey Shiori set Text [0 to "$n"] of View _input_ of View "$2" of Window "$1" to "" >/dev/null
}
send() { hey Shiori "$@" >/dev/null; }
# A BMessage by its 'what' code: msg <code> <specifier...>
msg() { hey Shiori "$@" >/dev/null; }

hey Shiori quit >/dev/null 2>&1
[ -f /boot/home/mh/fake.pid ] && kill "$(cat /boot/home/mh/fake.pid)" >/dev/null 2>&1
rm -rf "$(dirname "$CONFIG")"
python3 fake-services.py > "$LOG" 2>&1 &
echo $! > /boot/home/mh/fake.pid
sleep 1

# 1. First run: no settings, so Settings opens over the search window.
"$APP" >/boot/home/mh/app.log 2>&1 &
sleep 2
shot 01-first-run
settext "Shiori settings" server "http://127.0.0.1:8401/"
settext "Shiori settings" histerToken "FAKE-HISTER-TOKEN-0123"
settext "Shiori settings" kura "http://127.0.0.1:8402/"
settext "Shiori settings" roomToken "mht_KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK"
shot 02-settings-filled 0.5
msg Sdst of Window "Shiori settings"
sleep 1
mode=$(stat -c %a "$CONFIG" 2>/dev/null)
[ "$mode" = 600 ] && ok "config.json saved, mode 600" || bad "config.json mode is '$mode'"
grep -q '"roomToken": "mht_K' "$CONFIG" && ok "room token stored" || bad "room token not stored"

# 2. Search (All): notes from Kura, then pages from Hister.
settext Shiori query "haiku"
shot 03-search-all 2
grep -q 'hister GET /search' "$LOG" && ok "Hister searched" || bad "Hister not searched"
grep -q 'kura GET /api/search' "$LOG" && ok "Kura searched" || bad "Kura not searched"
grep -q 'query={"text":"(haiku|haiku\*) -label:vault -metadata.source:vault -type:local -metadata.source:code"' "$LOG" \
	&& ok "Hister got search-core's query" || bad "Hister's query differs"

# 3. The other pills.
msg Spil of Window Shiori with 'pill=int32(2)'
shot 04-pill-notes 2
msg Spil of Window Shiori with 'pill=int32(3)'
cleartext Shiori query
settext Shiori query "shiori"
shot 05-pill-code 2
grep -q 'metadata.source:code (shiori|shiori\*)' "$LOG" && ok "Code pill sends the code term" || bad "Code pill query"
msg Spil of Window Shiori with 'pill=int32(1)'
cleartext Shiori query
settext Shiori query "raspberry pi"
shot 06-pill-pages 2

# 4. Open a result in WebPositive.
# Select and invoke the first row (double-click's message).
send do Item 0 of View results of Window Shiori
sleep 4
shot 07-opened-in-webpositive 1
hey WebPositive quit >/dev/null 2>&1

# 5. Save a URL: from the clipboard, then a refused one.
echo -n "https://www.haiku-os.org/blog/" | clipboard -i 2>/dev/null || true
msg Ssav
sleep 1
settext "Save to Hister" title "Haiku blog"
settext "Save to Hister" label "haiku"
shot 08-save-filled 0.5
msg Sdsv of Window "Save to Hister"
shot 09-saved 1.5
grep 'hister POST /api/add' "$LOG" | grep "'origin': 'hister://'" | grep -q '"url": "https://www.haiku-os.org/blog/"' \
	&& ok "saved with Origin: hister://" || bad "save not seen"
grep -q '"via": "haiku", "ignore_skip_rules": true' "$LOG" && ok "newPage metadata" || bad "newPage metadata"
cleartext "Save to Hister" url
settext "Save to Hister" url "https://example.com/secret-token-page"
msg Sdsv of Window "Save to Hister"
shot 10-save-refused 1.5
send quit of Window "Save to Hister"
# A second launch hands its arguments to the running app (B_SINGLE_LAUNCH): `Shiori --save <url> [label]`.
"$APP" --save "https://www.haiku-os.org/news/" news >/dev/null 2>&1
sleep 1
shot 10b-save-from-terminal 0.5
msg Sdsv of Window "Save to Hister"
sleep 1.5
grep -q '"url": "https://www.haiku-os.org/news/", "title": "", "label": "news"' "$LOG" && ok "Shiori --save sent it" || bad "Shiori --save"
send quit of Window "Save to Hister"

# 6. The credential rules, end to end.
grep -q LEAK "$LOG" && bad "a credential went where it mustn't: $(grep LEAK "$LOG" | head -1)" || ok "no credential leaked"
grep 'kura GET' "$LOG" | grep -q "'x-access-token': '-'" && ok "Kura never got X-Access-Token" || bad "Kura header check"
grep 'hister GET /search' "$LOG" | grep -q "'authorization': '-'" && ok "Hister never got Authorization" || bad "Hister header check"

# 7. Settings persisted: quit, relaunch, search straight away.
hey Shiori quit >/dev/null 2>&1
sleep 1
"$APP" --query "kura" >/boot/home/mh/app.log 2>&1 &
shot 11-relaunched 3
hey Shiori count Window 2>/dev/null | grep -q '(B_INT32_TYPE) : 1 ' && ok "no Settings window on relaunch" || echo "note: window count $(hey Shiori count Window | grep result)"

# 8. Wrong credentials and a readable config: the status line says so, Settings warns.
hey Shiori quit >/dev/null 2>&1
sleep 1
cp "$CONFIG" /boot/home/mh/config.good
python3 - "$CONFIG" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
c["histerToken"] = "WRONG-TOKEN-999"
c["roomToken"] = ""
open(sys.argv[1], "w").write(json.dumps(c, indent=2))
PY
chmod 644 "$CONFIG"
"$APP" --query "haiku" >/boot/home/mh/app.log 2>&1 &
shot 12-wrong-credentials 3
msg Sset
shot 13-settings-warns-mode 1
hey Shiori quit >/dev/null 2>&1
cp /boot/home/mh/config.good "$CONFIG"
chmod 600 "$CONFIG"

# 9. Signing in to Hister (the fake has users): Settings offers it, the
# window signs in, Hister then gets the session cookie and Kura the mhs_ id,
# Sign Out ends both. First without the token, so the session is what works.
hey Shiori quit >/dev/null 2>&1
sleep 1
python3 - "$CONFIG" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
c["histerToken"] = ""
open(sys.argv[1], "w").write(json.dumps(c, indent=2))
PY
"$APP" >/boot/home/mh/app.log 2>&1 &
sleep 2
msg Sset
sleep 2
shot 14-settings-offers-sign-in 0.5
msg Ssin of Window "Shiori settings"
sleep 1
settext "Sign in to Hister" name "alex"
settext "Sign in to Hister" password "wrong-password"
msg Sdsi of Window "Sign in to Hister"
shot 15-sign-in-refused 1.5
grep -q 'hister POST /api/login' "$LOG" && ok "login sent" || bad "login not sent"
cleartext "Sign in to Hister" name
settext "Sign in to Hister" name "alex"
settext "Sign in to Hister" password "fake-password"
msg Sdsi of Window "Sign in to Hister"
sleep 2
shot 16-signed-in 0.5
SIGNIN=/boot/home/config/settings/Shiori/sign-in.json
mode=$(stat -c %a "$SIGNIN" 2>/dev/null)
[ "$mode" = 600 ] && ok "sign-in.json saved, mode 600" || bad "sign-in.json mode is '$mode'"
grep -q '"sid": "mhs_' "$SIGNIN" && ok "the helper's id kept" || bad "no id in sign-in.json"
grep -q 'fake-password' "$SIGNIN" "$CONFIG" /boot/home/mh/app.log && bad "the password was written down" || ok "the password isn't kept"
send quit of Window "Shiori settings"
cleartext Shiori query
settext Shiori query "beos"
shot 17-search-signed-in 2
grep 'hister GET /search' "$LOG" | tail -1 | grep -q "'x-access-token': '-'" && ok "Hister searched without the token" || bad "token still sent"
grep 'kura GET' "$LOG" | tail -1 | grep -q "'authorization': 'mhs_" && ok "Kura got the mhs_ id" || bad "Kura didn't get the id"
msg Sset
sleep 1
msg Ssou of Window "Shiori settings"
sleep 2
shot 18-signed-out 0.5
grep -q 'hister POST /machiya/signout' "$LOG" && ok "signed out through the helper" || bad "sign-out not sent"
[ ! -f "$SIGNIN" ] && ok "sign-in.json removed" || bad "sign-in.json still there"
send quit of Window "Shiori settings"
hey Shiori quit >/dev/null 2>&1
cp /boot/home/mh/config.good "$CONFIG"
chmod 600 "$CONFIG"
grep -q LEAK "$LOG" && bad "a credential went where it mustn't: $(grep LEAK "$LOG" | head -1)" || ok "no credential leaked (signed in)"

# 10. The outbox: with Hister away a save is kept (0600), and goes on the
# next drain once Hister is back, with its first time.
OUTBOX=/boot/home/config/settings/Shiori/outbox
rm -rf "$OUTBOX"
"$APP" >/boot/home/mh/app.log 2>&1 &
sleep 2
kill "$(cat /boot/home/mh/fake.pid)" >/dev/null 2>&1
sleep 1
"$APP" --save "https://www.haiku-os.org/community/" queued >/dev/null 2>&1
sleep 1
msg Sdsv of Window "Save to Hister"
shot 19-kept-for-later 2
n=$(ls "$OUTBOX"/*.json 2>/dev/null | wc -l)
[ "$n" -eq 1 ] && ok "kept in the outbox" || bad "outbox holds $n"
mode=$(stat -c %a "$(ls "$OUTBOX"/*.json | head -1)" 2>/dev/null)
[ "$mode" = 600 ] && ok "outbox entry mode 600" || bad "outbox entry mode is '$mode'"
grep -q -i 'token\|mhs_\|hister=' "$OUTBOX"/*.json && bad "a credential was stored in the outbox" || ok "no credential in the outbox"
send quit of Window "Save to Hister"
python3 fake-services.py >> "$LOG" 2>&1 &
echo $! > /boot/home/mh/fake.pid
sleep 1
msg Sdrn
sleep 2
grep 'hister POST /api/add' "$LOG" | grep '"url": "https://www.haiku-os.org/community/"' | grep -q '"added": [0-9]' \
	&& ok "the drain sent it, with its first time" || bad "the drain didn't send it"
n=$(ls "$OUTBOX"/*.json 2>/dev/null | wc -l)
[ "$n" -eq 0 ] && ok "outbox empty after the drain" || bad "outbox still holds $n"
hey Shiori quit >/dev/null 2>&1

echo "--- fake services log"
cat "$LOG"
exit $fail
