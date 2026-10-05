#!/usr/bin/env bash
# Doctor for verify-when-is-bin: "is this checkout and device worth driving?"
# Read-only apart from `git fetch` updating remote-tracking refs.
# Usage: .claude/skills/verify-when-is-bin/scripts/doctor.sh [<simulator-udid>]
#   ALLOW_BEHIND=1  only when Jess said to verify an older build on purpose.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
UDID="${1:-${UDID:-}}"
BUNDLE_ID=com.jessicamumby.whenIsBinApp
fail=0

git fetch origin --quiet || { echo "FAIL: git fetch"; fail=1; }
if counts=$(git rev-list --left-right --count origin/main...HEAD 2>/dev/null); then
  read -r behind ahead <<<"$counts"
else
  echo "FAIL: no origin/main"; behind=0; ahead=0; fail=1
fi
echo "branch=$(git rev-parse --abbrev-ref HEAD) head=$(git rev-parse --short HEAD) origin/main=$(git rev-parse --short origin/main) ahead=$ahead behind=$behind"
dirty=$(git status --porcelain | wc -l | tr -d ' ')
echo "uncommitted_files=$dirty$([ "$dirty" -gt 0 ] && echo ' (verdict Build line must say +uncommitted)')"
if [ "$behind" -gt 0 ] && [ "${ALLOW_BEHIND:-0}" != 1 ]; then
  echo "REFUSE: $behind commits behind origin/main. Rebase or merge origin/main first, or set ALLOW_BEHIND=1 only if Jess said so."
  fail=1
fi

if [ -f .env ]; then
  echo ".env present"
  base=$(grep -E '^WHENISBINS_BASE_URL=' .env | cut -d= -f2- | tr -d "\"' ")
  host=$(printf '%s' "${base:-https://whenisbins.com/v1}" | sed -E 's#^https?://##; s#/.*##')
  echo "api_host=$host (expected whenisbins.com: the live API; there is no staging)"
  [ "$host" = "whenisbins.com" ] || { echo "WARN: api_host is not whenisbins.com; say so in the verdict"; }
  if grep -qE '^WHENISBINS_API_TOKEN=.+' .env; then echo "api_token=set (value not shown)"; else echo "api_token=empty (anonymous: about 35 requests a day per IP, roughly two onboarding drives)"; fi
  # No API request here: the last block find_postcode_only.sh saw, if any.
  rl=.verify-runs/.rate-limited-until
  if [ -f "$rl" ] && [ "$(cat "$rl")" -gt "$(date +%s)" ]; then
    echo "WARN: api_allowance=spent until $(date -r "$(cat "$rl")" '+%a %d %b %H:%M %Z') (recorded by find_postcode_only.sh). API drives are INCONCLUSIVE until then; fixture drives still run."
  else
    echo "api_allowance=no block recorded (find_postcode_only.sh is the check; it costs one request)"
  fi
else
  echo "FAIL: .env missing (cp .env.example .env)"; fail=1
fi

booted=$(xcrun simctl list devices booted 2>/dev/null | grep Booted || true)
echo "${booted:-no booted simulator}"
if [ -n "$UDID" ]; then
  if printf '%s' "$booted" | grep -q "$UDID"; then
    echo "simulator $UDID booted"
    if xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" >/dev/null 2>&1; then
      echo "app installed on $UDID (state unknown until launched; drives that need first launch uninstall first)"
    else
      echo "app not installed on $UDID"
    fi
  else
    echo "FAIL: simulator $UDID not booted"; fail=1
  fi
fi
xcrun devicectl list devices 2>/dev/null | grep -i physical | grep -vi unavailable || echo "no physical iOS device reachable"

echo "doctor_exit=$fail"
exit $fail
