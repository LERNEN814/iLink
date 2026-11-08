#!/bin/sh
set -eu
[ "$(id -u)" = 0 ] || { echo "Run as root" >&2; exit 1; }
TOKEN=$(cat /etc/ilink/device_token)
for endpoint in status clients network; do
    code=$(curl -sS -o "/tmp/ilink-$endpoint.json" -w '%{http_code}' \
        --max-time 10 -H "Authorization: Bearer $TOKEN" \
        "http://127.0.0.1:8089/v1/$endpoint")
    [ "$code" = 200 ] || { echo "$endpoint failed: HTTP $code" >&2; exit 1; }
    grep -q '"apiVersion":1' "/tmp/ilink-$endpoint.json"
    echo "$endpoint: OK"
done
code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 \
    http://127.0.0.1:8089/v1/status)
[ "$code" = 401 ] || { echo "Unauthenticated request was not rejected" >&2; exit 1; }
code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 \
    http://127.0.0.1:8089/ubus)
[ "$code" = 404 ] || { echo "Unexpected /ubus route" >&2; exit 1; }
echo "Authentication and route restrictions: OK"
