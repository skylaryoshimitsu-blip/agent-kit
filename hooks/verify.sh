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

# Protected Vercel previews: send the automation bypass if it's in the environment.
bypass=()
if [ -n "${VERCEL_AUTOMATION_BYPASS_SECRET:-}" ]; then
  bypass=(-H "x-vercel-protection-bypass: $VERCEL_AUTOMATION_BYPASS_SECRET" -H "x-vercel-set-bypass-cookie: true")
fi
meta="$(curl -sSL --max-time 20 "${bypass[@]}" -o "$tmp/body" -w '%{http_code} %{size_download} %{time_total}' "$url" 2>"$tmp/err")"
read -r code size secs <<<"$meta"
code="${code:-000}"

if [[ "$code" =~ ^2 ]]; then notes+=("status $code · ${size} bytes · ${secs}s")
else fails+=("status $code $(head -c 200 "$tmp/err")"); fi

if [ -n "$expect" ]; then
  if grep -qF -- "$expect" "$tmp/body"; then notes+=("found expected text: \"$expect\"")
  else fails+=("expected text not found: \"$expect\""); fi
fi

# Placeholder scan: page plus up to 10 same-site scripts.
# Placeholders anywhere (page + its scripts). localhost is only checked in the page itself:
# libraries ship their own localhost defaults (e.g. supabase-js has localhost:9999), which
# are not our config.
PLACEHOLDERS='YOUR_[A-Z_]+|your-project|<your[-_ ]|REPLACE_ME|CHANGEME|xxxxxxxx|placeholder\.supabase|example\.supabase\.co'
page_local="$(grep -oE 'localhost:[0-9]+' "$tmp/body" | sort -u | head -3 | tr '\n' ' ')"
cp "$tmp/body" "$tmp/scan"
# ID templates inside libraries (e.g. 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx' for UUIDs) are not
# placeholders; remove them before scanning (lesson L-006).
origin="$(printf '%s' "$url" | grep -oE '^https?://[^/]+')"
grep -oE '<script[^>]+src="[^"]+"' "$tmp/body" | sed -E 's/.*src="([^"]+)"/\1/' | head -10 | while read -r src; do
  case "$src" in
    http*) [[ "$src" == "$origin"* ]] || continue; full="$src" ;;
    //*) continue ;;
    /*) full="$origin$src" ;;
    *) full="${url%/}/$src" ;;
  esac
  curl -sSL --max-time 15 "${bypass[@]}" "$full" >> "$tmp/scan" 2>/dev/null
done
sed -E 's/[xX]{8}-[xX]{4}-[0-9xX]{4}-[0-9xXyY]{4}-[xX]{12}//g' "$tmp/scan" > "$tmp/scan2" && mv "$tmp/scan2" "$tmp/scan"
hits="$(grep -oE "$PLACEHOLDERS" "$tmp/scan" | sort -u | head -5 | tr '\n' ' ')$page_local"
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
