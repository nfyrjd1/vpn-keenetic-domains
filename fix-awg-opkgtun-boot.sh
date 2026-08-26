#!/bin/sh

set -e

S52="/opt/etc/init.d/S52awg-opkgtun0"
S89="/opt/etc/init.d/S89amnezia-wg-quick"
K89="/opt/etc/init.d/K89amnezia-wg-quick"
HOOK="/opt/etc/ndm/wan.d/99-awg-opkgtun-restart.sh"
SRC="https://gitlab.com/ShidlaSGC/keenetic-entware-awg-go/-/raw/main/blob/02__KeenOS_5.0_(OpkgTun)/S52awg-opkgtun0"
SRC2="https://raw.githubusercontent.com/belenkiy-lab/Keenetic-Entware-AWG-Go-Manual/main/blob/02__KeenOS_5.0_(OpkgTun)/S52awg-opkgtun0"

die() { echo "ERROR: $*" >&2; exit 1; }

[ "$(id -u)" = "0" ] || die "run as root on the router"

mkdir -p /opt/etc/init.d /opt/etc/ndm/wan.d /opt/var/run /opt/var/log

echo "==> disable awg-quick autostart (S89 -> K89)"
if [ -f "$S89" ]; then
    mv "$S89" "$K89"
    echo "    renamed $S89 -> $K89"
elif [ -f "$K89" ]; then
    echo "    already disabled: $K89"
else
    echo "    no S89/K89 found (ok)"
fi

echo "==> remove leftover S52*.bak from init.d (S??* is autostarted)"
rm -f /opt/etc/init.d/S52awg-opkgtun0.bak*

echo "==> download original S52"
TMP="/tmp/S52awg.$$"
trap 'rm -f "$TMP" "$S52.tmp"' EXIT
if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$SRC" -o "$TMP" || curl -fsSL "$SRC2" -o "$TMP" || die "download failed"
elif command -v wget >/dev/null 2>&1; then
    wget -qO "$TMP" "$SRC" || wget -qO "$TMP" "$SRC2" || die "download failed"
else
    die "need curl or wget"
fi
grep -q "cmd_start" "$TMP" || die "downloaded file does not look like S52awg-opkgtun0"

echo "==> patch from scratch"
awk '
function ndmc_wait() {
    print "    # --- AWG-OPKGTUN BOOTFIX ndmc ---"
    print "    _i=0"
    print "    while [ -z \"$KEENOS_VER_MAJOR\" ] && [ \"${_i:-0}\" -lt 30 ]; do"
    print "        KEENOS_VER_MAJOR=$(ndmc -c \"show version\" 2>/dev/null | tr -d \"\\r\" | grep -o \"title: [0-9]\" | cut -d\" \" -f2)"
    print "        KEENOS_VER=$(ndmc -c \"show version\" 2>/dev/null | tr -d \"\\r\" | grep -oE \"title: [0-9.]+\" | cut -d\" \" -f2)"
    print "        KEENOS_VER_MAJOR=$(echo \"$KEENOS_VER_MAJOR\" | tr -d \"\\r\" | grep -oE \"[0-9]\" | head -n1)"
    print "        [ -n \"$KEENOS_VER_MAJOR\" ] && break"
    print "        sleep 2"
    print "        _i=$((_i + 1))"
    print "    done"
    print "    KEENOS_VER_MAJOR=$(echo \"$KEENOS_VER_MAJOR\" | tr -d \"\\r\" | grep -oE \"[0-9]\" | head -n1)"
    print "    [ -z \"$KEENOS_VER_MAJOR\" ] && KEENOS_VER_MAJOR=0"
    print "    # --- AWG-OPKGTUN BOOTFIX ndmc end ---"
}
function start_lock() {
    print "    # --- AWG-OPKGTUN BOOTFIX lock ---"
    print "    _LOCKDIR=\"/opt/var/run/S52awg-opkgtun0.lock\""
    print "    trap \"rmdir /opt/var/run/S52awg-opkgtun0.lock 2>/dev/null\" EXIT"
    print "    _lk=0"
    print "    while ! mkdir \"$_LOCKDIR\" 2>/dev/null; do"
    print "        if pgrep -f \"/opt/bin/$PROCS $OPKGTUN_INTERFACE\" >/dev/null; then"
    print "            log \"ℹ️ AmneziaWG for \\e[3m$OPKGTUN_INTERFACE\\e[0m already running (lock).\""
    print "            echo \"\" && return 0"
    print "        fi"
    print "        [ \"${_lk:-0}\" -ge 90 ] && die \"❌ Another S52 start is stuck (lock timeout).\""
    print "        sleep 1"
    print "        _lk=$((_lk + 1))"
    print "    done"
    print "    # --- AWG-OPKGTUN BOOTFIX lock end ---"
}
function boot_wait() {
    print "    # --- AWG-OPKGTUN BOOTFIX wait ---"
    print "    log \"ℹ️ Waiting for Keenetic interface \\e[3m$OPKGTUN_INTERFACE\\e[0m...\""
    print "    _wait_if=60"
    print "    while [ ! -d \"/sys/class/net/$OPKGTUN_INTERFACE\" ] && [ \"${_wait_if:-0}\" -gt 0 ]; do"
    print "        sleep 1 && _wait_if=$((_wait_if - 1))"
    print "    done"
    print "    [ -d \"/sys/class/net/$OPKGTUN_INTERFACE\" ] || die \"❌ Interface \\e[3m$OPKGTUN_INTERFACE\\e[0m did not appear.\""
    print "    log \"ℹ️ Waiting for clock/NTP before starting AWG...\""
    print "    _w=0"
    print "    while [ \"${_w:-0}\" -lt 60 ]; do"
    print "        _year=$(date +%Y 2>/dev/null | tr -d \"\\r\")"
    print "        if [ -n \"$_year\" ] && [ \"$_year\" -ge 2024 ] 2>/dev/null; then"
    print "            log \"ℹ️ Clock ready: $_year\""
    print "            break"
    print "        fi"
    print "        sleep 2"
    print "        _w=$((_w + 1))"
    print "    done"
    print "    sleep 5"
    print "    # --- AWG-OPKGTUN BOOTFIX wait end ---"
}
{
    if ($0 ~ /\[ \"\$KEENOS_VER_MAJOR\" -lt 5 \]/ && !ndmc_done) {
        ndmc_wait()
        ndmc_done = 1
    }
    if ($0 ~ /need restart this interface/ && !lock_done) {
        print
        getline
        print
        start_lock()
        lock_done = 1
        next
    }
    if ($0 ~ /Starting AmneziaWG/ && !wait_done) {
        boot_wait()
        wait_done = 1
    }
    print
}
END {
    if (!ndmc_done) exit 10
    if (!lock_done) exit 11
    if (!wait_done) exit 12
}
' "$TMP" > "$S52.tmp" || {
    rc=$?
    rm -f "$TMP" "$S52.tmp"
    [ "$rc" = "10" ] && die "upstream S52: KeenOS version check not found"
    [ "$rc" = "11" ] && die "upstream S52: already-running block not found"
    [ "$rc" = "12" ] && die "upstream S52: Starting AmneziaWG not found"
    die "awk patch failed ($rc)"
}
rm -f "$TMP"
mv "$S52.tmp" "$S52"
chmod +x "$S52"
grep -q "AWG-OPKGTUN BOOTFIX wait end" "$S52" || die "patch incomplete"

echo "==> install wan.d hook $HOOK"
cat > "$HOOK" << 'HOOK'
#!/bin/sh
# Start AWG only if the daemon is still down after WAN is up.
# Never restart/stop. Exit immediately: Keenetic runs ndm hooks in one queue.
export PATH="/opt/sbin:/opt/bin:/usr/sbin:/usr/bin:/sbin:/bin"

[ "$1" = "start" ] || exit 0

case "$interface" in
    *[Oo]pkg[Tt]un*) exit 0 ;;
esac

S52="/opt/etc/init.d/S52awg-opkgtun0"
LOG="/opt/var/log/awg-opkgtun-wan.log"
PGREP_PAT="/opt/bin/amneziawg-go opkgtun0"
[ -x "$S52" ] || exit 0

(
    i=0
    while [ "$i" -lt 45 ]; do
        if pgrep -f "$PGREP_PAT" >/dev/null 2>&1; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') already running, skip (interface=${interface:-empty})" >> "$LOG"
            exit 0
        fi
        sleep 2
        i=$((i + 1))
    done
    echo "$(date '+%Y-%m-%d %H:%M:%S') wan.d start, daemon was down (interface=${interface:-empty})" >> "$LOG"
    "$S52" start >> "$LOG" 2>&1
) &
exit 0
HOOK
chmod +x "$HOOK"

echo "OK. Downloaded upstream S52, patched, hook installed."
echo "    $S52 start"
echo "Log: /opt/var/log/awg-opkgtun-wan.log"
