import Foundation

nonisolated enum UpdateInstallerService {
    // Arguments: original PID, source, destination, result, open, ditto, mv, wait limit, poll interval.
    // The command seams let XCTest exercise the actual installer using only temporary fixtures.
    static let script = #"""
    trap '' HUP
    umask 077
    ORIGINAL_PID=$1
    SRC=$2
    DEST=$3
    RESULT=$4
    OPEN=$5
    COPY=$6
    MOVE=$7
    WAIT_LIMIT=$8
    POLL_INTERVAL=$9
    STAGE=
    BACKUP=
    OLD_EXITED=0

    write_file() {
        [ ! -d "$1" ] && [ ! -L "$1" ] || return 1
        RESULT_TEMP=$(/usr/bin/mktemp "${1}.XXXXXX") || return 1
        if ! printf '%s\n' "$2" > "$RESULT_TEMP"; then
            return 1
        fi
        /bin/mv -f "$RESULT_TEMP" "$1"
    }

    write_result() {
        write_file "$RESULT" "$1"
    }

    exists() {
        [ -e "$1" ] || [ -L "$1" ]
    }

    rename_app() {
        # mv must never merge a bundle into an existing directory.
        if exists "$2"; then
            return 1
        fi
        "$MOVE" "$1" "$2"
    }

    fail() {
        trap - 0 INT TERM
        REASON=$1
        RECOVERY=$DEST
        if [ -n "$BACKUP" ] && exists "$BACKUP"; then
            RECOVERY=$BACKUP
            CAN_RESTORE=1
            if exists "$DEST"; then
                if ! rename_app "$DEST" "$STAGE"; then
                    CAN_RESTORE=0
                fi
            fi
            if [ "$CAN_RESTORE" -eq 1 ] && rename_app "$BACKUP" "$DEST"; then
                RECOVERY=$DEST
            else
                REASON=rollback-failed
            fi
        fi
        if ! write_result "$REASON"; then
            # The previous atomic phase marker survives if storage becomes unwritable.
            printf '%s\n' 'result-write-failed' >&2
        fi
        if ! kill -0 "$ORIGINAL_PID" 2>/dev/null; then
            OLD_EXITED=1
        fi
        if [ "$OLD_EXITED" -eq 1 ] && [ -d "$RECOVERY" ]; then
            if ! "$OPEN" "$RECOVERY"; then
                if ! write_result relaunch-failed; then
                    printf '%s\n' 'result-write-failed' >&2
                fi
            fi
        fi
        exit 1
    }

    trap 'fail installer-failed' 0
    trap 'fail interrupted' INT TERM

    if ! write_result waiting-for-exit; then
        fail result-write-failed
    fi
    ATTEMPTS=0
    while kill -0 "$ORIGINAL_PID" 2>/dev/null; do
        if [ "$ATTEMPTS" -ge "$WAIT_LIMIT" ]; then
            fail exit-timeout
        fi
        /bin/sleep "$POLL_INTERVAL" || fail wait-failed
        ATTEMPTS=$((ATTEMPTS + 1))
    done
    OLD_EXITED=1

    [ -d "$DEST" ] && [ ! -L "$DEST" ] || fail destination-missing
    [ -d "$SRC" ] && [ ! -L "$SRC" ] || fail copy-failed
    if ! write_result copying; then
        fail result-write-failed
    fi
    # All bundle moves stay in DEST's parent, on the same filesystem. The original
    # and copied bundles are retained on failure; the backup also survives success.
    STAGE=$(/usr/bin/mktemp -d "${DEST%/*}/.LightStatsUpdate.XXXXXX") || fail staging-failed
    BACKUP="${STAGE}.backup.app"
    if exists "$BACKUP"; then
        BACKUP=
        fail staging-failed
    fi
    "$COPY" "$SRC" "$STAGE" || fail copy-failed
    # Local receipt handoff only: one absolute path plus newline, retained even on rollback.
    # Publish before moving the old bundle so recovery can recognize a launch from BACKUP.
    if ! write_file "${RESULT}.backup" "$BACKUP"; then
        fail backup-write-failed
    fi
    if ! write_result replacing; then
        fail result-write-failed
    fi
    rename_app "$DEST" "$BACKUP" || fail replace-failed
    rename_app "$STAGE" "$DEST" || fail replace-failed

    # Recovery runs as soon as the app launches, so publish BEFORE asking open to launch.
    if ! write_result installed; then
        fail result-write-failed
    fi
    "$OPEN" "$DEST" || fail relaunch-failed
    trap - 0 INT TERM
    exit 0
    """#

    /// Returns after spawning the independent shell, without waiting for the current app to exit.
    /// The caller owns staging and result storage, and must preserve them until installation finishes.
    /// Read resultURL.path + ".backup" for the retained bundle path; remove it only after confirming launch.
    static func launch(stagedApp: URL, destination: URL, resultURL: URL, ownership: FileHandle) throws {
        try Data("waiting-for-exit\n".utf8).write(to: resultURL, options: .atomic)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", script, "light-stats-installer",
            String(ProcessInfo.processInfo.processIdentifier),
            stagedApp.path, destination.path, resultURL.path,
            "/usr/bin/open", "/usr/bin/ditto", "/bin/mv", "120", "0.5"
        ]
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        // Keep the cross-process flock alive after the parent exits. The script never reads stdin.
        process.standardInput = ownership
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}
