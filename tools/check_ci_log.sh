#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="${1:-/tmp/suite.log}"
if [ ! -f "$LOG_FILE" ]; then
  echo "::error::CI log file not found: $LOG_FILE"
  exit 1
fi

if grep -Eq 'SCRIPT ERROR|Failed loading resource|Cannot open file|Condition ".*" is true|FAIL_SYNC_CAP:' "$LOG_FILE"; then
  echo "::error::engine reported load or sync-cap errors during the suite"
  grep -En 'SCRIPT ERROR|Failed loading resource|Cannot open file|Condition ".*" is true|FAIL_SYNC_CAP:' "$LOG_FILE"
  exit 1
fi

if grep -Eq 'UNRESOLVED_AI_PROFILE|SIDECAR_CONTENT_REFUSED|\[sidecar\] warning|dropped .*aiProfile' "$LOG_FILE"; then
  echo "::error::unresolved-ai-profile warning or refusal detected in CI log"
  grep -En 'UNRESOLVED_AI_PROFILE|SIDECAR_CONTENT_REFUSED|\[sidecar\] warning|dropped .*aiProfile' "$LOG_FILE"
  exit 1
fi

echo "CI log gate passed: $LOG_FILE"
