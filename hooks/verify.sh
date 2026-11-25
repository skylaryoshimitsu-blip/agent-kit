#!/usr/bin/env bash
# Verify a deployed page is really live and posts the proof to #logs.
#
# Usage: hooks/verify.sh <url> [text that must appear in the page]
#
# Checks:
#  - HTTP status is 2xx
#  - optional expected text is present in the response body
#  - no placeholder values in the page or its same-site JS files
# Exit code 0 = pass, 1 = fail. Database checks are done separately (Supabase).
source "$(dirname "$0")/lib.sh"

url="${1:-}"
expect="${2:-}"
[ -z "$url" ] && { echo "usage: verify.sh <url> [expected text]" >&2; exit 2; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fails=(); notes=()

meta="$(curl -sSL --max-time 20 -o "$tmp/body" -w '%{http_code} %{size_download} %{time_total}' "$url" 2>"$tmp/err")"
read -r code size secs <<<"$meta"
code="${code:-000}"

if [[ "$code" =~ ^2 ]]; then notes+=("status $code · ${size} bytes · ${secs}s")
else fails+=("status $code $(head -c 200 "$tmp/err")"); fi

if [ -n "$expect" ]; then
  if grep -qF -- "$expect" "$tmp/body"; then notes+=("found expected text: \"$expect\"")
  else fails+=("expected text not found: \"$expect\""); fi
fi

# Placeholder scan: page plus up to 10 same-site scripts.
PLACEHOLDERS='YOUR_[A-Z_]+|your-project|<your[-_ ]|REPLACE_ME|CHANGEME|xxxxxxxx|placeholder\.supabase|example\.supabase\.co|localhost:[0-9]+'
cp "$tmp/body" "$tmp/scan"
origin="$(printf '%s' "$url" | grep -oE '^https?://[^/]+')"
grep -oE '<script[^>]+src="[^"]+"' "$tmp/body" | sed -E 's/.*src="([^"]+)"/\1/' | head -10 | while read -r src; do
  case "$src" in
    http*) [[ "$src" == "$origin"* ]] || continue; full="$src" ;;
    //*) continue ;;
    /*) full="$origin$src" ;;
    *) full="${url%/}/$src" ;;
  esac
  curl -sSL --max-time 15 "$full" >> "$tmp/scan" 2>/dev/null
done
hits="$(grep -oE "$PLACEHOLDERS" "$tmp/scan" | sort -u | head -5 | tr '\n' ' ')"
if [ -n "$hits" ]; then fails+=("placeholder values shipped: $hits")
else notes+=("no placeholder values found"); fi

if [ "${#fails[@]}" -eq 0 ]; then
  msg="✅ **Verified live** — $url"$'\n'"$(printf '• %s\n' "${notes[@]}")"
  rc=0
else
  msg="❌ **Verification failed** — $url"$'\n'"$(printf '• %s\n' "${fails[@]}" "${notes[@]}")"
  rc=1
fi
printf '%s\n' "$msg"
post logs "$msg"
exit $rc
