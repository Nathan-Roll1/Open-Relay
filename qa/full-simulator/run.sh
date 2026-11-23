#!/usr/bin/env bash
set -euo pipefail
e="$RUNNER_TEMP/openrelay-evidence";mkdir -p "$e"
test "$(git diff --name-only 1b72fcb9400c79c96d7237347a50cf0c90be46e9 -- 'Open UI' 'Open UI.xcodeproj' 'App' 'OpenRelayWatch' 'OpenRelayWatchWidgets' 'OpenUIWidgets' 'OpenUIShareExtension' | wc -l | tr -d ' ')" = 0
openssl rand -hex 12 > "$RUNNER_TEMP/fourier-qa-password"
echo "::add-mask::$(cat "$RUNNER_TEMP/fourier-qa-password")"
bash qa/full-simulator/server.sh > "$RUNNER_TEMP/loopback-setup.log" 2>&1 &
backendpid=$!
cleanup(){ kill "$backendpid" >/dev/null 2>&1 || true; }
trap cleanup EXIT
for try in $(seq 1 200); do
 if curl -fs --max-time 3 http://127.0.0.1:8319/health >/dev/null; then break; fi
 if ! kill -0 "$backendpid" 2>/dev/null; then grep -Ei '(error|failed|unsupported|no solution|traceback|not found)' "$RUNNER_TEMP/loopback-setup.log" | tail -25 | tee "$e/backend-failure.txt"; exit 1; fi
 sleep 4
done
curl -fs --max-time 5 http://127.0.0.1:8319/api/config | python3 -c 'import json,sys;x=json.load(sys.stdin); print("Stock Open WebUI",x.get("version"),"status",x.get("status"),"on 127.0.0.1")' | tee "$e/backend.txt"
# Check a genuine login succeeds outside the app without printing an access token.
python3 - <<'PY'
import os,pathlib,json,urllib.request
d={'email':'fourier-qa@example.test','password':pathlib.Path(os.environ['RUNNER_TEMP'],'fourier-qa-password').read_text().strip()}
r=urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:8319/api/v1/auths/signin',data=json.dumps(d).encode(),headers={'Content-Type':'application/json'}))
token=json.load(r)['token']; assert token
check=json.load(urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:8319/api/v1/auths/',headers={'Authorization':'Bearer '+token})))
assert check['email']==d['email']
p=pathlib.Path('qa/full-simulator/Tests/Journey.swift');p.write_text(p.read_text().replace('LOCAL_OPEN_WEBUI_PASSWORD',d['password']))
print('Verified ordinary email/password session against /api/v1/auths/ on loopback before build')
PY
brew list xcodegen >/dev/null 2>&1 || brew install xcodegen >/dev/null
xcodebuild -version
xcodebuild -downloadComponent MetalToolchain >/tmp/fourier-metal-install.log 2>&1
dev=$(xcrun simctl list devices available -j | python3 -c 'import json,sys;d=json.load(sys.stdin)["devices"];dev=[v for k in reversed(sorted(d)) if "iOS-26" in k for v in d[k] if v["isAvailable"] and "iPhone" in v["name"]];print(dev[0]["udid"])')
echo "$dev" > "$RUNNER_TEMP/openrelay-device"
xcrun simctl boot "$dev" || true
pack=/tmp/fourier-original-simulator-app.zip
if test -f "$pack"; then
  dest="$RUNNER_TEMP/original-simulator-app"; mkdir -p "$dest"; ditto -x -k "$pack" "$dest"
  app=$(find "$dest" -maxdepth 1 -name '*.app' -print -quit)
  echo "Restored original simulator app from exact-source, exact-Xcode cache" | tee "$e/build.txt"
else
xcodebuild -project 'Open UI.xcodeproj' -scheme 'Open UI' -configuration Debug \
  -destination "platform=iOS Simulator,id=$dev" -onlyUsePackageVersionsFromResolvedFile \
  -skipPackagePluginValidation -skipMacroValidation -derivedDataPath /tmp/openrelay-build \
  COMPILER_INDEX_STORE_ENABLE=NO build > /tmp/full-sim-build.log 2>&1 || { grep -m35 -E 'error:|fatal error|BUILD FAILED' /tmp/full-sim-build.log | tee "$e/build-failure.txt"; exit 1; }
grep -F '** BUILD SUCCEEDED **' /tmp/full-sim-build.log | tee "$e/build.txt"
app=$(find /tmp/openrelay-build/Build/Products/Debug-iphonesimulator -maxdepth 1 -name '*.app' -print -quit)
  test -n "$app"
  ditto -c -k --keepParent "$app" "$pack"
fi
xcrun simctl bootstatus "$dev" -b
xcrun simctl install "$dev" "$app"
(cd qa/full-simulator && xcodegen generate)
set +e
xcodebuild -project qa/full-simulator/FourierUI.xcodeproj -scheme Journey -destination "platform=iOS Simulator,id=$dev" -parallel-testing-enabled NO -derivedDataPath /tmp/fourier-ui -resultBundlePath /tmp/fourier-ui.xcresult test >/tmp/fourier-ui.log 2>&1
result=$?
set -e
grep -E 'FOURIER_UI|error:|failed \(|Executed [0-9]+ test|TEST SUCCEEDED|TEST FAILED' /tmp/fourier-ui.log | tail -70 | tee "$e/ui-milestones.txt" || true
# Export only the local service's route/status receipts and app category diagnostics.
python3 - "$RUNNER_TEMP/loopback-setup.log" "$e/backend-requests.txt" <<'PYBACK'
import sys,re,pathlib
s=pathlib.Path(sys.argv[1]).read_text(errors='replace')
routes=re.findall(r'\b(GET|POST|HEAD) (/[^ ?"]*?)(?:\?[^ "]+)? HTTP/[0-9.]+[" ]+([0-9]{3})',s)
pathlib.Path(sys.argv[2]).write_text('\n'.join(' '.join(row) for row in routes if row[1] in ['/health','/api/config','/api/v1/auths','/api/v1/auths/','/api/v1/auths/api_key','/api/v1/auths/signin'])+'\n')
PYBACK
xcrun simctl spawn "$dev" log show --last 12m --level info --predicate 'subsystem == "com.openui" AND (category == "Auth" OR category == "OnDeviceASR")' 2>/dev/null | grep -Ei 'connect|config|state|load|variant|error' | sed -E 's/(sk-[[:alnum:]_-]+|eyJ[[:alnum:]._-]+)/[redacted]/g' | tail -45 > "$e/app-routing.txt" || true
# Host-read only. Never seed or modify the application preferences or files.
container=$(xcrun simctl get_app_container "$dev" com.openui.openui data)
python3 - "$container" "$e/sandbox.json" <<'PY'
import json,pathlib,sys,plistlib
r=pathlib.Path(sys.argv[1]); pl=r/'Library/Preferences/com.openui.openui.plist'
pref=plistlib.loads(pl.read_bytes()) if pl.exists() else {}
paths=[(str(p.relative_to(r)),p.stat().st_size) for p in r.rglob('*') if 'fourier' in str(p).lower() and (p.is_file() or p.name.startswith('models--'))]
result={'persisted_variant':pref.get('onDeviceASR.model'),'matching_model_cache':paths[:45]}
pathlib.Path(sys.argv[2]).write_text(json.dumps(result,indent=2));print(result)
PY
exit "$result"
