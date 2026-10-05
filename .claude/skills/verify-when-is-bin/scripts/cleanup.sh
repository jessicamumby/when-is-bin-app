#!/usr/bin/env bash
# Stops only what this run recorded in $RUN_DIR/started.txt, then proves the
# evidence survived. Never kills by process name, never erases a simulator,
# never removes .env or the evidence.
# started.txt lines: "sim <udid>" (this run booted it), "pid <pid> <what>",
# "recorder <pid>", "app <udid> <bundle-id>" (an app this run launched or kept
# running with --keep-app-running).
# Usage: .claude/skills/verify-when-is-bin/scripts/cleanup.sh "$RUN_DIR"
set -uo pipefail
RUN_DIR="${1:?usage: cleanup.sh <run-dir>}"
LIST="$RUN_DIR/started.txt"
if [ -f "$LIST" ]; then
  # Recorders and processes first, simulators last.
  while read -r kind id rest; do
    case "$kind" in
      recorder) kill -INT "$id" 2>/dev/null && echo "stopped recorder $id" ;;
      pid) kill "$id" 2>/dev/null && echo "stopped process $id" ;;
      app) xcrun simctl terminate "$id" "$rest" 2>/dev/null && echo "terminated $rest on $id" ;;
    esac
  done < "$LIST"
  while read -r kind id _; do
    if [ "$kind" = sim ]; then
      xcrun simctl shutdown "$id" 2>/dev/null && echo "shut down simulator $id (this run booted it)"
    fi
  done < "$LIST"
else
  echo "no started.txt: nothing recorded, nothing stopped"
fi
echo "retained: .env (repo convention), the installed debug app on the simulator, evidence below"
echo "evidence in $RUN_DIR:"
ls -1 "$RUN_DIR"
