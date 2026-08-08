#!/usr/bin/env bash
#
# Sets up production signing for Omni, end to end, in one command.
#
# Generates a release keystore, uploads it to GitHub Actions as secrets, and
# leaves the only copy somewhere outside this repository. After this runs,
# every release is signed with your key instead of the dev key checked in
# here — no console, no clicking, no base64 by hand.
#
# Run it from anywhere inside the repo:
#
#     ./tools/setup-release-signing.sh
#
# Requires: keytool (ships with any JDK) and gh (github.com/cli/cli),
# authenticated with `gh auth login`.

set -euo pipefail

readonly KEYSTORE_DIR="${OMNI_KEYSTORE_DIR:-$HOME/.omni-signing}"
readonly KEYSTORE_PATH="$KEYSTORE_DIR/omni-release.jks"
readonly KEY_ALIAS="omni"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
warn() { printf '\033[33m%s\033[0m\n' "$1"; }
fail() { printf '\033[31m%s\033[0m\n' "$1" >&2; exit 1; }

# --- checks ----------------------------------------------------------------

command -v keytool >/dev/null 2>&1 ||
  fail "keytool not found. Install a JDK (e.g. 'brew install temurin' or
'apt install default-jdk') and try again."

command -v gh >/dev/null 2>&1 ||
  fail "gh not found. Install the GitHub CLI from https://cli.github.com and
run 'gh auth login', then try again."

gh auth status >/dev/null 2>&1 ||
  fail "gh is installed but not signed in. Run 'gh auth login' first."

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)" ||
  fail "Couldn't work out which GitHub repo this is. Run this from inside a
clone of the Omni repository."

# --- the key itself --------------------------------------------------------

if [ -f "$KEYSTORE_PATH" ]; then
  bold "A keystore already exists at $KEYSTORE_PATH"
  echo
  warn "Reusing it. Generating a NEW key would break updates for anyone who"
  warn "already installed a build signed with the old one — Android treats a"
  warn "different key as a different app."
  echo
  printf 'Password for the existing keystore: '
  read -rs STORE_PASS
  echo
  keytool -list -keystore "$KEYSTORE_PATH" -storepass "$STORE_PASS" \
    >/dev/null 2>&1 || fail "That password doesn't open $KEYSTORE_PATH."
else
  bold "Creating a release keystore"
  echo
  echo "This key signs every future release. It cannot be changed later"
  echo "without breaking updates for existing installs, so it is worth"
  echo "backing up properly — this script will remind you at the end."
  echo

  mkdir -p "$KEYSTORE_DIR"
  chmod 700 "$KEYSTORE_DIR"

  # Generated rather than chosen: this password is only ever pasted into a
  # secret store, so a memorable one buys nothing and costs entropy.
  STORE_PASS="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 40)"

  keytool -genkeypair -v \
    -keystore "$KEYSTORE_PATH" \
    -alias "$KEY_ALIAS" \
    -keyalg RSA -keysize 4096 \
    -validity 10000 \
    -storepass "$STORE_PASS" \
    -keypass "$STORE_PASS" \
    -dname "CN=Omni, OU=Omni, O=Omni, L=Unknown, ST=Unknown, C=US" \
    >/dev/null

  chmod 600 "$KEYSTORE_PATH"
  bold "Created $KEYSTORE_PATH"
fi

# --- upload to Actions -----------------------------------------------------

echo
bold "Uploading secrets to $REPO"

# base64 -w0 is GNU; macOS base64 has no -w and doesn't wrap by default.
if base64 --help 2>&1 | grep -q -- '-w'; then
  KEYSTORE_B64="$(base64 -w0 "$KEYSTORE_PATH")"
else
  KEYSTORE_B64="$(base64 "$KEYSTORE_PATH" | tr -d '\n')"
fi

printf '%s' "$KEYSTORE_B64" | gh secret set OMNI_KEYSTORE_BASE64 --repo "$REPO"
printf '%s' "$STORE_PASS"   | gh secret set OMNI_KEYSTORE_PASSWORD --repo "$REPO"
printf '%s' "$STORE_PASS"   | gh secret set OMNI_KEY_PASSWORD --repo "$REPO"
printf '%s' "$KEY_ALIAS"    | gh secret set OMNI_KEY_ALIAS --repo "$REPO"

echo
bold "Done. The next release will be signed with your key."

# --- what the human still has to do ---------------------------------------

FINGERPRINT="$(keytool -list -v -keystore "$KEYSTORE_PATH" \
  -storepass "$STORE_PASS" -alias "$KEY_ALIAS" 2>/dev/null |
  grep -i 'SHA256:' | head -1 | sed 's/^[[:space:]]*//')"

cat <<EOF

────────────────────────────────────────────────────────────────────────
Back this up now, while you are thinking about it.

  Keystore   $KEYSTORE_PATH
  Password   $STORE_PASS
  Alias      $KEY_ALIAS
  $FINGERPRINT

Put both the file and the password somewhere you will still have them in
five years — a password manager, plus an offline copy. If you lose them
you cannot ship an update to anyone who already installed Omni; they have
to uninstall and lose their sources and saved posts.

The keystore lives outside this repository on purpose. Do not move it in.
────────────────────────────────────────────────────────────────────────

One consequence to know about: builds from now on are signed differently
from the dev-signed pre-releases. Anyone running one of those has to
uninstall before they can install a new build. Right now that is a very
short list, which is why doing this early is worth it.
EOF
