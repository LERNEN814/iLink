#!/bin/sh
# One-click package upgrade with service restoration.
# Firmware is never touched here: iLink only links to LuCI for that.
RUNNING=$(cat /tmp/ilink-upgrade.services 2>/dev/null)
echo "START $(date)"
/bin/opkg update >/dev/null 2>&1
NAMES=$(/bin/opkg list-upgradable 2>/dev/null | awk '{print $1}' | grep -v '^Multiple$' | sort -u | tr '\n' ' ')
if [ -z "$NAMES" ]; then
    echo "NOTHING TO UPGRADE"
    echo "DONE $(date)"
    exit 0
fi
echo "UPGRADING: $NAMES"
# shellcheck disable=SC2086
if /bin/opkg upgrade $NAMES; then
    echo "UPGRADE OK"
else
    echo "ERROR: opkg upgrade reported a failure"
fi
for s in $RUNNING; do
    /etc/init.d/$s restart >/dev/null 2>&1 || /etc/init.d/$s start >/dev/null 2>&1
    echo "RESTARTED: $s"
done
echo "DONE $(date)"
