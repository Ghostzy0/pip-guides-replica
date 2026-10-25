#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$#" -gt 1 ]]; then echo "Usage: scripts/build-app.sh [baseline|baseline-enhanced|pip|pip-enhanced]" >&2; exit 2; fi
if [[ "$#" -eq 0 ]]; then
  edition="$(python3 scripts/release_integrity.py select-edition "$PWD")"
else
  edition="$(python3 scripts/release_integrity.py select-edition "$PWD" "$1")"
fi
case "$edition" in
 baseline) app_name="Guides Replica"; bundle_id="uk.pipreps.guides.replica"; app_version="0.1.0-alpha.1"; compiler_flags_json='["-DBASELINE","-DGUIDES_REPLICA"]' ;;
 baseline-enhanced) app_name="Guides Enhanced"; bundle_id="uk.pipreps.guides.baseline.enhanced"; app_version="0.1.0-alpha.2"; compiler_flags_json='["-DBASELINE","-DGUIDES_ENHANCEMENTS"]' ;;
 pip) app_name="Pip Guides"; bundle_id="uk.pipreps.guides"; app_version="0.1.0-alpha.1"; compiler_flags_json='[]' ;;
 pip-enhanced) app_name="Pip Guides Enhanced"; bundle_id="uk.pipreps.guides.enhanced"; app_version="0.1.0-alpha.2"; compiler_flags_json='["-DGUIDES_ENHANCEMENTS"]' ;;
 *) echo "Usage: scripts/build-app.sh [baseline|baseline-enhanced|pip|pip-enhanced]" >&2; exit 2 ;;
esac
signing_identity=""
if [[ -n "${PIP_GUIDES_SIGNING_IDENTITY:-}" ]]; then
  signing_identity="$PIP_GUIDES_SIGNING_IDENTITY"
elif [[ -e .local-signing-identity || -L .local-signing-identity ]]; then
  if [[ -L .local-signing-identity || ! -f .local-signing-identity ]]; then
    echo "The local signing identity configuration is invalid; no build was made." >&2
    exit 1
  fi
  if ! signing_identity="$(python3 - .local-signing-identity <<'PY'
import pathlib, re, sys
try:
    value = pathlib.Path(sys.argv[1]).read_bytes()
except OSError:
    raise SystemExit(1)
if value.endswith(b"\n"):
    value = value[:-1]
if not re.fullmatch(rb"[0-9A-Fa-f]{40}", value):
    raise SystemExit(1)
print(value.decode("ascii"))
PY
  )"; then
    echo "The local signing identity configuration is invalid; no build was made." >&2
    exit 1
  fi
fi
signing_mode="adhoc"
if [[ -n "$signing_identity" ]]; then
  if [[ ! "$signing_identity" =~ ^[[:xdigit:]]{40}$ ]]; then
    echo "The selected signing identity must be a 40-character fingerprint; no build was made." >&2
    exit 1
  fi
  normalized_identity="$(printf '%s' "$signing_identity" | tr '[:lower:]' '[:upper:]')"
  available_identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  if ! printf '%s\n' "$available_identities" | awk -v fingerprint="$normalized_identity" \
      '$1 ~ /^[0-9]+\)$/ && toupper($2) == fingerprint && ($3 " " $4) ~ /^"Apple Development:/ {found=1} END {exit !found}'; then
    echo "The selected signing identity must match an available Apple Development identity; no build was made." >&2
    exit 1
  fi
  signing_mode="apple-development"
fi
scratch=".build/$edition"
mkdir -p .build
input_manifest="$(mktemp -t pipguides-inputs)"
staging=""
cleanup() {
  rm -f "$input_manifest"
  if [[ -n "$staging" && -d "$staging" ]]; then rm -rf "$staging"; fi
}
trap cleanup EXIT
input_hash="$(python3 scripts/release_integrity.py manifest "$PWD" "$input_manifest")"
swift_build() {
  case "$edition" in
    baseline) swift build "$@" -Xswiftc -DBASELINE -Xswiftc -DGUIDES_REPLICA ;;
    baseline-enhanced) swift build "$@" -Xswiftc -DBASELINE -Xswiftc -DGUIDES_ENHANCEMENTS ;;
    pip-enhanced) swift build "$@" -Xswiftc -DGUIDES_ENHANCEMENTS ;;
    pip) swift build "$@" ;;
  esac
}
swift_build -c release --scratch-path "$scratch"
bin_path="$(swift_build -c release --scratch-path "$scratch" --show-bin-path)"
mkdir -p dist
staging="$(mktemp -d dist/.package.XXXXXX)"
app="$staging/$app_name.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_path/PipGuides" "$app/Contents/MacOS/PipGuides"
python3 - "$app" "$app_name" "$bundle_id" "$app_version" <<'PY'
import plistlib, sys
app,name,identifier,version=sys.argv[1:]
payload={"CFBundleExecutable":"PipGuides","CFBundleIdentifier":identifier,"CFBundleName":name,"CFBundleDisplayName":name,"CFBundleVersion":"2" if version.endswith(".2") else "1","CFBundleShortVersionString":version,"CFBundlePackageType":"APPL","LSMinimumSystemVersion":"14.0","NSHighResolutionCapable":True,"NSScreenCaptureUsageDescription":"Capture pictures only from the window you choose for a guide.","NSPrincipalClass":"NSApplication"}
with open(app+'/Contents/Info.plist','wb') as f: plistlib.dump(payload,f)
PY
python3 scripts/release_integrity.py receipt "$PWD" "$app" "$edition" "$input_manifest" "$input_hash" --compiler-flags-json "$compiler_flags_json" --signing-mode "$signing_mode"
if [[ "$signing_mode" == "adhoc" ]]; then
  codesign --force --sign - --identifier "$bundle_id" "$app"
else
  codesign --force --sign "$signing_identity" --identifier "$bundle_id" "$app"
fi
codesign --verify --deep --strict "$app"
python3 - "$app" "dist/$app_name.app" <<'PY2'
import pathlib, sys, uuid
staged, final = map(pathlib.Path, sys.argv[1:])
if final.exists() or final.is_symlink():
    final.rename(final.with_name('.previous-' + final.stem + '-' + uuid.uuid4().hex + '.app'))
staged.rename(final)
PY2
rmdir "$staging"
if [[ "$signing_mode" == "adhoc" ]]; then
  echo "Built dist/$app_name.app ($edition). Ad-hoc signed, not notarised. Previous local build preserved in dist/.previous-*.app."
else
  echo "Built dist/$app_name.app ($edition). Apple Development signed, not notarised. Previous local build preserved in dist/.previous-*.app."
fi
