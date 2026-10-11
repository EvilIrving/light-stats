#!/bin/bash
# Manual live-window checks. Never run in XCTest or CI.
set -euo pipefail
cd "$(dirname "$0")/.."
PROBE=./script/ax-probe.sh
APP_FILTER=""
ZONE_FILTER=all
SPEED_FILTER=normal
PER_APP=1
usage() {
    echo 'Usage: verify-window-snap.sh [--apps display-name,pid,...] [--zones all|zone,...] [--speeds normal,fast] [--per-app N]'
}
while [ "$#" -gt 0 ]; do
    case "$1" in
        --help) usage; exit 0 ;;
        --apps|--zones|--speeds|--per-app)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            case "$1" in
                --apps) APP_FILTER="$2" ;;
                --zones) ZONE_FILTER="$2" ;;
                --speeds) SPEED_FILTER="$2" ;;
                --per-app) PER_APP="$2" ;;
            esac
            shift 2 ;;
        *) usage; exit 2 ;;
    esac
done
[[ "$PER_APP" =~ ^[1-9][0-9]*$ ]] || { usage; exit 2; }
ALL_ZONES="$("$PROBE" zones)"
if [ "$ZONE_FILTER" = all ]; then read -r -a ZONES <<< "$ALL_ZONES";
else IFS=',' read -r -a ZONES <<< "$ZONE_FILTER"; fi
for zone in "${ZONES[@]}"; do
    [[ " $ALL_ZONES " = *" $zone "* ]] || { echo "Unknown zone: $zone"; exit 2; }
done
IFS=',' read -r -a SPEEDS <<< "$SPEED_FILTER"
for speed in "${SPEEDS[@]}"; do
    [[ "$speed" = normal || "$speed" = fast ]] || { usage; exit 2; }
done
[ "$("$PROBE" trust)" = trusted ] || exit 2
OWN_PID="$(pgrep -x 'Light Stats' | head -1)"
[ -n "$OWN_PID" ] || { echo 'Light Stats is not running'; exit 2; }
plutil -p "$HOME/Library/Preferences/cain.com.light-stats.plist" | grep -q '"settings.windowManagementEnabled" => true' || {
    echo 'Window management is disabled'; exit 2;
}
APPS_RAW="$("$PROBE" apps)"
APP_PIDS=()
while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    [ "${entry%%|*}" != "$OWN_PID" ] || continue
    if [ -n "$APP_FILTER" ]; then
        IFS=',' read -r -a WANTED <<< "$APP_FILTER"
        MATCH=false
        for wanted in "${WANTED[@]}"; do
            if [ "$wanted" = "${entry%%|*}" ] || [ "$wanted" = "${entry#*|}" ]; then MATCH=true; fi
        done
        "$MATCH" || continue
    fi
    APP_PIDS+=("$entry")
done <<< "$APPS_RAW"
[ "${APP_PIDS[*]-}" != '' ] || { echo 'No matching applications'; exit 2; }

mkdir -p build/window-snap-runs
RUN_DIR="$(mktemp -d build/window-snap-runs/run-XXXXXXXX)"
chmod 700 "$RUN_DIR"
exec > >(tee "$RUN_DIR/results.log") 2>&1
PASSED=0 FAILED=0 SKIPPED=0 ACTIVE=false
APP='' TITLE=''
pass_case() { PASSED=$((PASSED + 1)); echo "PASS $*"; }
fail_case() { FAILED=$((FAILED + 1)); echo "FAIL $*"; printf '%s | %s | %s\n' "$APP" "$TITLE" "$*" >> "$RUN_DIR/failures.txt"; }
skip_case() { SKIPPED=$((SKIPPED + 1)); echo "SKIP $*"; }
frames_equal() {
    python3 - "$1" "$2" "$3" <<'PY'
import math, sys
try:
    a, b = ([float(x) for x in arg.split()] for arg in sys.argv[1:3])
    ok = len(a) == len(b) == 4 and all(math.isfinite(x) and math.isfinite(y) and abs(x-y) <= float(sys.argv[3]) for x,y in zip(a,b))
except ValueError:
    ok = False
sys.exit(0 if ok else 1)
PY
}
restore() {
    local restored
    restored="$("$PROBE" place "$PID" "$TITLE" "$WX" "$WY" "$WW" "$WH")" || return 1
    sleep 0.3
    restored="$("$PROBE" frame "$PID" "$TITLE")" || return 1
    if ! frames_equal "$restored" "$ORIGINAL" 4; then
        fail_case "RESTORE expected=$ORIGINAL actual=$restored; stopping to preserve window state"
        return 1
    fi
}
cleanup() {
    local status=$?
    trap - EXIT
    if "$ACTIVE"; then restore || status=1; fi
    echo "通过 ${PASSED}，失败 ${FAILED}，跳过 ${SKIPPED}；结果 ${RUN_DIR}"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
printf 'App=%s zones=%s speeds=%s per-app=%s\n' "${#APP_PIDS[@]}" "${ZONES[*]}" "${SPEEDS[*]}" "$PER_APP"
/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' '/Applications/Light Stats.app/Contents/Info.plist'

for entry in "${APP_PIDS[@]}"; do
    PID="${entry%%|*}" APP="${entry#*|}"
    echo "=== $APP ($PID) ==="
    WINDOW_LINES="$("$PROBE" list "$PID")"
    WINDOW_INDEX=0
    while IFS='|' read -r role subrole TITLE ORIGINAL rest; do
        case "$subrole" in AXStandardWindow|AXDocumentWindow|AXFloatingWindow) ;; *) continue ;; esac
        [ "$WINDOW_INDEX" -lt "$PER_APP" ] || break
        WINDOW_INDEX=$((WINDOW_INDEX + 1))
        frames_equal "$ORIGINAL" "$ORIGINAL" 0 || { skip_case 'unreadable frame'; continue; }
        CURRENT="$("$PROBE" frame "$PID" "$TITLE")" || { skip_case 'missing or ambiguous title'; continue; }
        frames_equal "$CURRENT" "$ORIGINAL" 2 || { skip_case 'window changed during discovery'; continue; }
        read -r WX WY WW WH <<< "$ORIGINAL"
        printf '%s\t%s\t%s\n' "$PID" "$TITLE" "$ORIGINAL" >> "$RUN_DIR/original-frames.tsv"
        echo "Window=$TITLE original=$ORIGINAL"
        "$PROBE" raise "$PID" "$TITLE" || { skip_case 'cannot raise window'; continue; }
        sleep 0.5
        ACTIVE=true
        SCREEN_X=$((WX + WW / 2)) SCREEN_Y=$((WY + WH / 2))
        for ZONE in "${ZONES[@]}"; do
            EXPECTED="$("$PROBE" expected "$ZONE" "$SCREEN_X" "$SCREEN_Y")"
            DROP="$("$PROBE" drop-point "$ZONE" "$SCREEN_X" "$SCREEN_Y")"
            read -r DX DY <<< "$DROP"
            case "$ZONE" in left*|topLeft|bottomLeft|centerThird) START_ZONE=rightHalf ;; *) START_ZONE=leftHalf ;; esac
            START_FRAME="$("$PROBE" expected "$START_ZONE" "$SCREEN_X" "$SCREEN_Y")"
            read -r HX HY HW HH <<< "$START_FRAME"
            for SPEED in "${SPEEDS[@]}"; do
                SETUP="$("$PROBE" place "$PID" "$TITLE" "$HX" "$HY" "$HW" "$HH")"
                if ! frames_equal "$SETUP" "$START_FRAME" 4; then
                    fail_case "$ZONE/$SPEED SETUP expected=$START_FRAME actual=$SETUP"
                    restore; continue
                fi
                sleep 0.3
                GRAB="$("$PROBE" grab "$PID" "$TITLE")" || { skip_case "$ZONE/$SPEED no verified grab point"; restore; continue; }
                read -r GX GY <<< "$GRAB"
                MARK="$("$PROBE" mark)"
                if [ "$SPEED" = fast ]; then STEPS=8 HOLD=0; else STEPS=30 HOLD=120000; fi
                "$PROBE" drag "$GX" "$GY" "$DX" "$DY" "$STEPS" 16000 "$HOLD"
                sleep 1.8
                GOT="$("$PROBE" frame "$PID" "$TITLE")" || GOT=none
                VERDICT="$("$PROBE" journal "$MARK" succeeded failed dragRejected)"
                printf '%s/%s %s\n' "$ZONE" "$SPEED" "$VERDICT" >> "$RUN_DIR/journal.log"
                restore
                if frames_equal "$GOT" "$EXPECTED" 4 && [[ "$VERDICT" = *' succeeded '* ]]; then
                    pass_case "$ZONE/$SPEED frame=$GOT"
                else
                    fail_case "$ZONE/$SPEED expected=$EXPECTED actual=$GOT journal=$VERDICT"
                fi
            done
        done
        GRAB="$("$PROBE" grab "$PID" "$TITLE")" || GRAB=none
        if [ "$GRAB" = none ]; then skip_case 'scroll: no grab point';
        else
            read -r GX GY <<< "$GRAB"
            "$PROBE" scroll "$GX" "$GY" -24 6 10
            sleep 1.8
            GOT="$("$PROBE" frame "$PID" "$TITLE")" || GOT=none
            restore
            if frames_equal "$GOT" "$ORIGINAL" 2; then pass_case 'scroll: unchanged';
            else fail_case "scroll expected=$ORIGINAL actual=$GOT"; fi
        fi
        restore
        ACTIVE=false
    done <<< "$WINDOW_LINES"
    [ "$WINDOW_INDEX" -gt 0 ] || skip_case 'no standard window'
done
[ "$FAILED" -eq 0 ] || exit 1
[ "$PASSED" -gt 0 ] || exit 2
