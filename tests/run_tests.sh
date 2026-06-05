#!/bin/bash
# ─────────────────────────────────────────────────────
#  amalgame-webauthn — Test Runner
#  Usage: ./tests/run_tests.sh [/path/to/amc]
#
#  Builds the WebAuthn facade against a sibling amalgame-crypto
#  checkout (AM-facade dependency wired via --external), compiles +
#  links the test sample, runs it, and asserts the [PASS] lines.
# ─────────────────────────────────────────────────────
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ $# -ge 1 ]; then AMC="$1"
elif [ -n "${AMC:-}" ]; then :
elif command -v amc >/dev/null 2>&1; then AMC="$(command -v amc)"
else echo "ERROR: amc not found (arg / AMC env / PATH)." >&2; exit 2; fi
[ -x "$AMC" ] || { echo "ERROR: amc '$AMC' not executable" >&2; exit 2; }

AMC_DIR="$(cd "$(dirname "$AMC")" && pwd)"
if [ -n "${AMC_RUNTIME:-}" ] && [ -d "$AMC_RUNTIME" ]; then :
elif [ -d "$AMC_DIR/runtime" ]; then AMC_RUNTIME="$AMC_DIR/runtime"
elif [ -d "$AMC_DIR/share/amalgame/runtime" ]; then AMC_RUNTIME="$AMC_DIR/share/amalgame/runtime"
elif [ -d "$PKG_DIR/../Amalgame/runtime" ]; then AMC_RUNTIME="$PKG_DIR/../Amalgame/runtime"
else echo "ERROR: amc runtime/ not found; set AMC_RUNTIME" >&2; exit 2; fi

# ── Locate sibling amalgame-crypto ─────────────────────
if [ -n "${AMALGAME_CRYPTO:-}" ] && [ -d "$AMALGAME_CRYPTO" ]; then
    CRYPTO_DIR="$AMALGAME_CRYPTO"
elif [ -d "$PKG_DIR/../amalgame-crypto" ]; then
    CRYPTO_DIR="$PKG_DIR/../amalgame-crypto"
elif [ -d "$HOME/.amalgame/packages/github.com/amalgame-lang/amalgame-crypto" ]; then
    CRYPTO_DIR="$(ls -d "$HOME/.amalgame/packages/github.com/amalgame-lang/amalgame-crypto"/*/ 2>/dev/null | tail -1)"
    CRYPTO_DIR="${CRYPTO_DIR%/}"
fi
if [ -z "${CRYPTO_DIR:-}" ] || [ ! -f "$CRYPTO_DIR/facade.am" ]; then
    echo "ERROR: amalgame-crypto not found (set AMALGAME_CRYPTO or check out as a sibling)" >&2
    exit 2
fi

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
echo "  amc:     $AMC ($("$AMC" --version 2>&1))"
echo "  runtime: $AMC_RUNTIME"
echo "  crypto:  $CRYPTO_DIR"

BUILD_DIR="$(mktemp -d -t awa-tests-XXXXXX)"
trap 'rm -rf "$BUILD_DIR"; rm -f "$PKG_DIR/_test.am"' EXIT

# ── Build crypto facade (.o) ───────────────────────────
( cd "$CRYPTO_DIR" && "$AMC" --lib -o "$BUILD_DIR/crypto" facade.am ) 2>&1 | tail -10
gcc -O2 -I"$AMC_RUNTIME" -I"$CRYPTO_DIR" -c "$BUILD_DIR/crypto.c" -o "$BUILD_DIR/crypto.o" 2>"$BUILD_DIR/gcc.log"; head -6 "$BUILD_DIR/gcc.log"
[ -s "$BUILD_DIR/crypto.o" ] || { echo -e "${RED}crypto build failed${NC}"; cat "$BUILD_DIR/gcc.log"; exit 1; }

# ── Build webauthn facade (.o) ─────────────────────────
( cd "$PKG_DIR" && "$AMC" --lib -o "$BUILD_DIR/facade" facade.am --external "$CRYPTO_DIR/facade.am" ) 2>&1 | tail -10
gcc -O2 -I"$AMC_RUNTIME" -I"$CRYPTO_DIR" -c "$BUILD_DIR/facade.c" -o "$BUILD_DIR/facade.o" 2>"$BUILD_DIR/gcc.log"; head -6 "$BUILD_DIR/gcc.log"
[ -s "$BUILD_DIR/facade.o" ] || { echo -e "${RED}facade build failed${NC}"; cat "$BUILD_DIR/gcc.log"; exit 1; }

# ── Build + run the test sample ────────────────────────
cp "$SCRIPT_DIR/stdlib_webauthn.am" "$PKG_DIR/_test.am"
( cd "$PKG_DIR" && "$AMC" -o "$BUILD_DIR/test" _test.am \
    --external "$CRYPTO_DIR/facade.am" --external facade.am ) 2>&1 | tail -10
gcc -O2 -I"$AMC_RUNTIME" -I"$CRYPTO_DIR" "$BUILD_DIR/test.c" "$BUILD_DIR/facade.o" "$BUILD_DIR/crypto.o" \
    -lgc -lm -lssl -lcrypto -lpthread -o "$BUILD_DIR/test" 2>"$BUILD_DIR/gcc.log"; head -10 "$BUILD_DIR/gcc.log"
[ -x "$BUILD_DIR/test" ] || { echo -e "${RED}test build failed${NC}"; cat "$BUILD_DIR/gcc.log"; exit 1; }

OUT="$("$BUILD_DIR/test" 2>&1)"
echo "$OUT"

PASS=0; FAIL=0
check() {
    if echo "$OUT" | grep -qF "$1"; then PASS=$((PASS+1));
    else FAIL=$((FAIL+1)); echo -e "  ${RED}MISSING${NC}: $1"; fi
}
check "[PASS] NewChallenge: 43-char base64url, unique"
check "[PASS] registration extracts COSE key + credId"
check "[PASS] registration rejects wrong origin"
check "[PASS] registration rejects challenge mismatch"
check "[PASS] assertion signature verifies + counter advances"
check "[PASS] assertion rejects tampered signature"
check "[PASS] assertion rejects non-increasing counter (clone)"
check "[PASS] assertion rejects rpIdHash mismatch"

echo "────────────────────────────────────────────"
echo -e "  ${GREEN}PASS: $PASS${NC}  |  ${RED}FAIL: $FAIL${NC}"
echo "────────────────────────────────────────────"
[ "$FAIL" -eq 0 ]
