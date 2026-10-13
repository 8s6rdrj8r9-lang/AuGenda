#!/bin/bash
# Validate Google OAuth values in an expanded built-product Info.plist.
# Unconfigured builds are valid because Google sign-in is optional.

set -u

PLIST_PATH="${1:-${TARGET_BUILD_DIR:-}/${INFOPLIST_PATH:-}}"
if [ ! -f "$PLIST_PATH" ]; then
    echo "error: pass the expanded built-product Info.plist to validate-oauth.sh"
    exit 2
fi

CLIENT_ID=$(/usr/libexec/PlistBuddy -c "Print :AuGendaGoogleClientID" "$PLIST_PATH" 2>/dev/null || true)
REDIRECT_SCHEME=$(/usr/libexec/PlistBuddy -c "Print :AuGendaGoogleRedirectScheme" "$PLIST_PATH" 2>/dev/null || true)

case "$CLIENT_ID:$REDIRECT_SCHEME" in
    *YOUR_CLIENT_ID*:*|*'$('*:*|:*YOUR_CLIENT_ID*|:*'$('*|:)
        echo "note: Google OAuth is not configured; sign-in remains disabled"
        exit 0
        ;;
esac

if [ -z "$CLIENT_ID" ] || [ -z "$REDIRECT_SCHEME" ]; then
    echo "error: Google OAuth client ID and redirect scheme must be configured together"
    exit 1
fi

EXPECTED_SCHEME=$(printf '%s\n' "$CLIENT_ID" | awk -F. '{
    for (i = NF; i >= 1; i--) {
        printf "%s%s", $i, (i > 1 ? "." : "\n")
    }
}')
if [ "$EXPECTED_SCHEME" != "$REDIRECT_SCHEME" ]; then
    echo "error: Google OAuth redirect scheme is not the reversed client ID"
    exit 1
fi

REGISTERED=$(/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:0:CFBundleURLSchemes" "$PLIST_PATH" 2>/dev/null || true)
if ! printf '%s\n' "$REGISTERED" | grep -Fqx "    $REDIRECT_SCHEME" \
    && ! printf '%s\n' "$REGISTERED" | grep -Fqx "$REDIRECT_SCHEME"; then
    echo "error: Google OAuth redirect scheme is not registered in CFBundleURLTypes"
    exit 1
fi

echo "Google OAuth configuration is consistent."
