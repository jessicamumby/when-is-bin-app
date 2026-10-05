#!/usr/bin/env bash
# Find a postcode the live WhenIsBins API answers as postcode-only today:
# required_input "none" (or "property_id" with an empty candidate list), which
# is what sends onboarding to the field-less address form.
# Read-only: GET /addresses only, anonymous, honours Retry-After up to MAX_WAIT
# seconds (default 300), then stops rather than sleeping for the long window.
# Usage: .claude/skills/verify-when-is-bin/scripts/find_postcode_only.sh ["PC1 1AA" "PC2 2BB" ...]
# Prints one line per postcode; lines starting "POSTCODE-ONLY" are usable.
# Budget: the anonymous allowance ran out after roughly 35 requests in a day
# (Retry-After 81893s on 5 October 2026), and the app on the simulator shares
# it. Probe a handful at a time.
# Prefer a hit with a low expected_wait and success_rate near 1: a slow or
# failing council stalls the drive on the address form (see the feature file).
set -uo pipefail
hdr=$(mktemp); trap 'rm -f "$hdr"' EXIT
BASE="${WHENISBINS_BASE_URL:-https://whenisbins.com/v1}"
if [ "$#" -gt 0 ]; then set -- "$@"; else
  # Default: the only postcode-only answer seen on 5 October 2026 (Shetland).
  # CB4 2HX, the postcode in the fix's unit test, listed addresses that day.
  set -- "ZE1 0AA"
fi
for pc in "$@"; do
  for attempt in 1 2 3 4; do
    body=$(curl -s -m 20 -D "$hdr" -G "$BASE/addresses" --data-urlencode "postcode=$pc")
    if grep -q '^HTTP/[0-9.]* 429' "$hdr" || printf '%s' "$body" | grep -q '"rate_limited"'; then
      wait=$(grep -i '^retry-after:' "$hdr" | tr -dc '0-9'); wait=${wait:-20}
      if [ "$wait" -gt "${MAX_WAIT:-300}" ]; then
        echo "RATE-LIMITED: anonymous allowance spent; retry after ${wait}s (the app on the simulator shares this limit). Stopping."; exit 2
      fi
      sleep "$wait"; continue
    fi
    break
  done
  printf '%s' "$body" | python3 -c '
import json, sys
pc = sys.argv[1]
try:
    d = json.load(sys.stdin)
except Exception:
    print(f"ERROR {pc}: unreadable answer"); sys.exit()
c = d.get("council") if isinstance(d.get("council"), dict) else {}
ri, cands = d.get("required_input"), d.get("candidates") or []
only = ri == "none" or (ri == "property_id" and not cands)
notice = (d.get("source_notice") or {}).get("problem", "")
tag = "POSTCODE-ONLY" if only else "needs-address"
if d.get("problem"):
    tag = "ERROR"
name, wait, rate = c.get("name"), c.get("expected_wait_seconds"), c.get("success_rate")
extra = ("notice=" + notice) if notice else ""
problem = d.get("problem") or ""
print(f"{tag} {pc}: council={name} required_input={ri} candidates={len(cands)} "
      f"expected_wait={wait}s success_rate={rate} {extra}{problem}")
' "$pc"
  sleep 6
done
