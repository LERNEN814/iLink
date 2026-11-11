#!/bin/sh
set -eu

# Run only after reviewing the DDNSTO and security notes in README.md.
[ "$(id -u)" = 0 ] || { echo "Run as root" >&2; exit 1; }
BASE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
for file in ilink-upgrade.sh ilink-streamd.lua gateway.lua upload.cgi gateway.cgi module.cgi urlcode.lua openclash.lua files.lua fastnet.lua alist.lua downloader.lua systeminfo.lua ubus-acl.json rpcd-acl.json ilink.init rpcd/ilink-action; do
    [ -f "$BASE/$file" ] || { echo "Missing $file" >&2; exit 1; }
done
for command in uhttpd lua openssl useradd groupadd chpasswd uci; do
    command -v "$command" >/dev/null || { echo "Missing $command" >&2; exit 1; }
done
[ -s /etc/uhttpd.crt ] && [ -s /etc/uhttpd.key ] || {
    echo "The existing uhttpd TLS certificate is required" >&2; exit 1;
}

if ! grep -q '^ilink:' /etc/group; then groupadd -r ilink; fi
if ! id ilink >/dev/null 2>&1; then
    useradd -r -g ilink -d /var/empty -M -s /bin/false ilink
fi

# Replace the v0.1 development prefix-script, if present, with fixed CGI files.
[ ! -f /usr/lib/ilink/www/v1 ] || rm -f /usr/lib/ilink/www/v1
mkdir -p /etc/ilink /usr/lib/ilink/www/v1
chown root:ilink /etc/ilink /usr/lib/ilink /usr/lib/ilink/www /usr/lib/ilink/www/v1
chmod 0750 /etc/ilink /usr/lib/ilink /usr/lib/ilink/www /usr/lib/ilink/www/v1
# Keep LuCI's private key root-only; iLink gets its own service-readable copy.
cp /etc/uhttpd.crt /etc/ilink/uhttpd.crt
cp /etc/uhttpd.key /etc/ilink/uhttpd.key
chown root:ilink /etc/ilink/uhttpd.crt /etc/ilink/uhttpd.key
chmod 0640 /etc/ilink/uhttpd.crt /etc/ilink/uhttpd.key
cp "$BASE/gateway.lua" /usr/lib/ilink/gateway.lua
for module in urlcode openclash files fastnet alist downloader systeminfo; do
    cp "$BASE/$module.lua" "/usr/lib/ilink/$module.lua"
    chown root:ilink "/usr/lib/ilink/$module.lua"
    chmod 0750 "/usr/lib/ilink/$module.lua"
done
for directory in openclash files fastnet alist downloader system; do
    mkdir -p "/usr/lib/ilink/www/v1/$directory"
    chown root:ilink "/usr/lib/ilink/www/v1/$directory"
    chmod 0750 "/usr/lib/ilink/www/v1/$directory"
done
cp "$BASE/upload.cgi" "/usr/lib/ilink/www/v1/files/upload-raw"
chown root:ilink "/usr/lib/ilink/www/v1/files/upload-raw"
chmod 0751 "/usr/lib/ilink/www/v1/files/upload-raw"
for endpoint in openclash/status openclash/groups openclash/connections openclash/select openclash/test-delay openclash/group-delay openclash/close openclash/overview openclash/subscription openclash/ipcheck openclash/configs openclash/mode openclash/service openclash/switch-config files/list files/mkdir files/rename files/remove files/download files/stream files/stream-ticket files/upload files/copy files/move files/preview fastnet/quick fastnet/nat fastnet/ipv6 alist/list alist/mkdir alist/rename alist/remove alist/upload alist/download downloader/submit downloader/jobs downloader/remove system/services system/updates system/upgrade system/upgrade-status system/traffic system/exec system/firmware system/network-snapshot system/network-backups system/network-restore system/network-confirm; do
    cp "$BASE/module.cgi" "/usr/lib/ilink/www/v1/$endpoint"
    chown root:ilink "/usr/lib/ilink/www/v1/$endpoint"
    chmod 0751 "/usr/lib/ilink/www/v1/$endpoint"
done
SECRET=$(uci -q get openclash.config.dashboard_password || true)
if [ -n "$SECRET" ]; then
    printf '%s\n' "$SECRET" > /etc/ilink/clash_secret
    chown root:ilink /etc/ilink/clash_secret
    chmod 0640 /etc/ilink/clash_secret
fi
CONFIG=$(uci -q get openclash.config.config_path || true)
if [ -n "$CONFIG" ]; then printf '%s\n' "$CONFIG" > /etc/ilink/clash_config; fi
chown root:ilink /etc/ilink/clash_config
chmod 0640 /etc/ilink/clash_config
unset SECRET CONFIG
chown root:ilink /usr/lib/ilink/gateway.lua
chmod 0750 /usr/lib/ilink/gateway.lua
for endpoint in status clients network; do
    cp "$BASE/gateway.cgi" "/usr/lib/ilink/www/v1/$endpoint"
    chown root:ilink "/usr/lib/ilink/www/v1/$endpoint"
    # uhttpd explicitly requires S_IXOTH for CGI programs.
    chmod 0751 "/usr/lib/ilink/www/v1/$endpoint"
done
mkdir -p /usr/libexec/rpcd
cp "$BASE/rpcd/ilink-action" /usr/libexec/rpcd/ilink-action
chown root:root /usr/libexec/rpcd/ilink-action
chmod 0755 /usr/libexec/rpcd/ilink-action
cp "$BASE/ilink-upgrade.sh" /usr/libexec/ilink-upgrade.sh
chown root:root /usr/libexec/ilink-upgrade.sh
chmod 0755 /usr/libexec/ilink-upgrade.sh
cp "$BASE/ilink-streamd.lua" /usr/libexec/ilink-streamd.lua
chown root:root /usr/libexec/ilink-streamd.lua
chmod 0755 /usr/libexec/ilink-streamd.lua
chown root:root /usr/libexec/ilink-upgrade.sh
chmod 0755 /usr/libexec/ilink-upgrade.sh
cp "$BASE/rpcd-acl.json" /usr/share/rpcd/acl.d/ilink.json
chown root:root /usr/share/rpcd/acl.d/ilink.json
chmod 0644 /usr/share/rpcd/acl.d/ilink.json
cp "$BASE/ubus-acl.json" /usr/share/acl.d/ilink.json
chown root:root /usr/share/acl.d/ilink.json
chmod 0644 /usr/share/acl.d/ilink.json
if pidof ubusd >/dev/null 2>&1; then kill -HUP "$(pidof ubusd)"; fi
cp "$BASE/ilink.init" /etc/init.d/ilink
chown root:root /etc/init.d/ilink
chmod 0755 /etc/init.d/ilink

if [ ! -s /etc/ilink/device_token ]; then
    openssl rand -hex 32 > /etc/ilink/device_token
fi
RPC_PASSWORD=$(openssl rand -hex 32)
printf '%s\n' "$RPC_PASSWORD" > /etc/ilink/rpcd_password
printf 'ilink:%s\n' "$RPC_PASSWORD" | chpasswd
unset RPC_PASSWORD
# AList credentials are written once (by the operator) and kept across upgrades.
[ -e /etc/ilink/alist_credentials ] || : > /etc/ilink/alist_credentials
chown root:ilink /etc/ilink/alist_credentials
chmod 0640 /etc/ilink/alist_credentials
chown root:ilink /etc/ilink/device_token /etc/ilink/rpcd_password
chmod 0640 /etc/ilink/device_token /etc/ilink/rpcd_password

mkdir -p /etc/ilink/backup
cp /etc/config/rpcd "/etc/ilink/backup/rpcd.$(date +%Y%m%d%H%M%S)"
uci -q delete rpcd.ilink || true
uci set rpcd.ilink=login
uci set rpcd.ilink.username=ilink
uci set rpcd.ilink.password='$p$ilink'
uci -q delete rpcd.ilink.read || true
uci -q delete rpcd.ilink.write || true
uci add_list rpcd.ilink.read=ilink-read
uci commit rpcd

/etc/init.d/rpcd restart
/etc/init.d/ilink enable
/etc/init.d/ilink restart

LAN_IP=$(uci -q get network.lan.ipaddr)
printf '\nGateway installed. No LuCI, SSH or generic /ubus route was created.\n'
printf 'LAN URL: https://%s:8443\n' "$LAN_IP"
printf 'DDNSTO target: http://127.0.0.1:8089\n'
printf 'LAN certificate: '
openssl x509 -in /etc/uhttpd.crt -noout -fingerprint -sha256
printf '\nPhone token (copy to iLink; keep private):\n'
cat /etc/ilink/device_token
printf '\nTest locally: sh %s/test.sh\n' "$BASE"
