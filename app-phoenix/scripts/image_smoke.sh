#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."

IMAGE="${IMAGE:-dawarich:a0-local}"
PLATFORM="${PLATFORM:-}"
WAIT="${SMOKE_WAIT_SECONDS:-300}"
export DAWARICH_APP_PORT=3900
override="$(mktemp)"
work="$(mktemp -d)"
override_off="$(mktemp)"
{
  echo "services:"
  echo "  dawarich_redis:"
  echo "    container_name: a0_redis"
  echo "  dawarich_db:"
  echo "    container_name: a0_db"
  echo "  dawarich_app:"
  echo "    container_name: a0_app"
  echo "    image: $IMAGE"
  [ -z "$PLATFORM" ] || echo "    platform: $PLATFORM"
  echo "  dawarich_sidekiq:"
  echo "    container_name: a0_sidekiq"
  echo "    image: $IMAGE"
  [ -z "$PLATFORM" ] || echo "    platform: $PLATFORM"
} >"$override"
compose="docker compose -p phoenix-a0 -f docker/docker-compose.yml -f $override"

cleanup() {
  ec=$?
  $compose down -v >/dev/null 2>&1 || true
  rm -f "$override"
  rm -rf "$work" "$override_off"
  exit "$ec"
}
trap cleanup EXIT
trap 'exit 1' INT TERM

fail() {
  echo "$1" >&2
  exit 1
}

owner="$(docker run --rm ${PLATFORM:+--platform "$PLATFORM"} --user 0 --entrypoint sh "$IMAGE" -c \
  'mkdir -p /tmp/owned && chown 1000:1000 /tmp/owned && DAWARICH_COOKIE_FILE=/tmp/owned/cookie dawarich eval "IO.puts(:ok)" >/dev/null && stat -c %u:%g /tmp/owned/cookie')"
[ "$owner" = "1000:1000" ] || fail "a cookie created by root belongs to $owner, not to its directory's owner"

$compose up -d
tries=0
until [ "$(docker inspect -f '{{.State.Health.Status}}' a0_app)" = "healthy" ]; do
  tries=$((tries + 1))
  [ "$tries" -lt $((WAIT / 5)) ] || fail "app not healthy"
  sleep 5
done

docker exec a0_app ps -o comm= -p 1 | grep -q beam || fail "PID 1 is not the BEAM"
docker exec a0_app ps -eo args | grep -qE '^puma|bin/rails server' || fail "puma not running"
[ "$(docker exec a0_app dawarich rpc 'IO.puts(Oban.config().prefix)')" = "oban" ] || fail "rpc failed"
[ "$(docker exec a0_app dawarich rpc 'IO.puts(Dawarich.HtmlSanitizer.sanitize("<b>x</b><script>y</script>"))')" = "<b>x</b>y" ] \
  || fail "the image's lazy_html NIF cannot sanitize HTML"
docker exec a0_app sh -c 'cd /var/app && test -s config/sprockets-manifest.json && test -s tmp/phoenix/i18n.json && test -s tmp/phoenix/achievements.json && test -s tmp/phoenix/importmap.json' \
  || fail "a build input is missing from the image"
upstream="$(docker logs a0_app 2>&1 | sed -n 's/.*Phoenix listens on \[::\]:3000 and proxies to Puma on 127\.0\.0\.1:\([0-9][0-9]*\).*/\1/p' | tail -1)"
[ -n "$upstream" ] || fail "Phoenix does not front Puma on [::]:3000"
rails_css="$(docker exec a0_app bin/rails runner 'puts ActionController::Base.helpers.asset_path("tailwind.css")' 2>/dev/null | tail -1)"
printf '%s' "$rails_css" | grep -qE '^/assets/tailwind-[0-9a-f]{64}\.css$' \
  || fail "Rails does not resolve tailwind.css to a digested asset through the manifest: '$rails_css'"
[ "$(docker exec a0_app dawarich rpc 'IO.puts(DawarichWeb.Assets.stylesheet_path("tailwind.css"))')" = "$rails_css" ] \
  || fail "Phoenix and Rails link different tailwind.css files"
for base in http://127.0.0.1:3000 "http://127.0.0.1:$upstream"; do
  docker exec -i a0_app sh -s -- /var/app/public_dist "$rails_css" "$base" 127.0.0.1:3900 <app-phoenix/scripts/served_asset_check.sh \
    || fail "$base does not serve the image's built tailwind.css"
done
[ "$(docker exec a0_app dawarich rpc 'IO.puts(match?({:ok, _}, Dawarich.I18n.t("de", "common.app_name")) and length(Dawarich.Achievements.Registry.all()) > 200 and length(Dawarich.TimeZoneOptions.list()) > 100 and String.starts_with?(DawarichWeb.Assets.rails_imports()["application"], "/assets/application-"))')" = true ] \
  || fail "Phoenix cannot read a build input"
curl -fsS "http://127.0.0.1:$DAWARICH_APP_PORT/api/v1/health" | grep -q '"status"' || fail "health failed"
docker exec a0_db psql -U postgres -d dawarich_development -Atc \
  "SELECT string_agg(nspname, ',' ORDER BY nspname) FROM pg_namespace WHERE nspname IN ('oban','phoenix')" \
  | grep -qx 'oban,phoenix' || fail "schemas missing"
docker exec a0_app dawarich help | grep -q 'raw-data restore USER_ID YEAR MONTH' || fail "dawarich help is not routed to the CLI"
docker exec a0_app dawarich migrate status | grep -qx 'public schema: current' || fail "migrate status does not see a current public schema"
docker exec a0_app dawarich jobs status | grep -q '"summary"' || fail "jobs status did not print its JSON"
[ "$(docker exec a0_app dawarich 'points:raw_data:status' | head -1 | wc -c | tr -d ' ')" = 139 ] || fail "raw-data status through the rake name failed or re-encoded its header"
docker exec -u 0 a0_app dawarich raw-data status >/dev/null || fail "the CLI fails as root"
docker exec a0_app sh -c 'printf "%s\n" phoenix-a12e-smoke-login-not-for-production | dawarich users password demo@dawarich.app' >/dev/null || fail "users password failed"
[ "$(docker exec a0_app bin/rails runner 'print User.find_by(email: "demo@dawarich.app").valid_password?("phoenix-a12e-smoke-login-not-for-production")' 2>/dev/null | tail -1)" = true ] \
  || fail "Rails does not accept the password the CLI set"
set +e
docker exec a0_app dawarich jobs resume 00000000-0000-4000-8000-00000000a12e >"$work/resume.out" 2>&1
resume=$?
set -e
[ "$resume" -eq 1 ] && grep -q 'is not a failed or stalled release operation' "$work/resume.out" || fail "jobs resume did not reach the release operations (exit $resume)"
echo "docker stats: $(docker stats --no-stream --format '{{.Name}} {{.MemUsage}} {{.CPUPerc}}' a0_app)"

docker exec a0_app sh -c 'cat /proc/net/tcp /proc/net/tcp6' | awk '$4 == "0A" {print $2}' >"$work/listeners"
grep -q ':0BB8$' "$work/listeners" || fail "nothing listens on 3000"
if grep -v ':0BB8$' "$work/listeners" | grep -vqE '^([0-9A-F]{6}7F|00000000000000000000000001000000):'; then
  fail "a listener other than Phoenix's is reachable from outside the container"
fi

norm() { tr -d '\r' | sed 1d | awk -F': ' 'NF > 1 {print tolower($1) ": " $2}' | grep -vE '^(date|set-cookie|x-request-id|x-runtime|etag|connection|keep-alive|content-length): ' | sort; }
curl -fsS -D - -o /dev/null -H 'Host: 127.0.0.1:3900' http://127.0.0.1:3900/api/v1/health | norm >"$work/through"
docker exec a0_app curl -fsS -D - -o /dev/null -H 'Host: 127.0.0.1:3900' "http://127.0.0.1:$upstream/api/v1/health" | norm >"$work/direct"
diff "$work/direct" "$work/through" || fail "proxied health headers differ from Puma's"
curl -fsS -D - -o /dev/null http://127.0.0.1:3900/users/sign_in | norm | cut -d: -f1 >"$work/through-names"
docker exec a0_app curl -fsS -D - -o /dev/null -H 'Host: 127.0.0.1:3900' "http://127.0.0.1:$upstream/users/sign_in" | norm | cut -d: -f1 >"$work/direct-names"
diff "$work/direct-names" "$work/through-names" || fail "proxied page header names differ from Puma's"
notifications_head="$(curl -s -o /dev/null -D - http://127.0.0.1:3900/notifications)"
printf '%s' "$notifications_head" | grep -qi '^location: http://127.0.0.1:3900/users/sign_in' || fail "a signed-out /notifications does not redirect to sign in"
if printf '%s' "$notifications_head" | grep -qi '^x-runtime:'; then fail "Rails answered /notifications, not Phoenix"; fi

docker exec a0_app curl --version | grep -q ' ws ' || fail "the image's curl cannot speak WebSocket; this check needs another client"
docker exec a0_app curl -sS -m 10 -D - --output - -H 'Origin: http://127.0.0.1:3000' \
  -H 'Sec-WebSocket-Protocol: actioncable-v1-json, actioncable-unsupported' ws://127.0.0.1:3000/cable 2>/dev/null \
  | LC_ALL=C tr -d '\r' >"$work/cable" || true
grep -q '^HTTP/1.1 101' "$work/cable" || fail "the /cable upgrade did not come through Phoenix"
grep -qi '^sec-websocket-protocol: actioncable-v1-json' "$work/cable" || fail "Puma's subprotocol did not reach the client"
grep -aq 'unauthorized' "$work/cable" || fail "ActionCable's refusal did not reach the client"

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
docker exec a0_app sh -c 'head -c 209715200 /dev/urandom >/var/app/public/a2-stream.bin'
expected="$(docker exec a0_app sha256sum /var/app/public/a2-stream.bin | cut -d' ' -f1)"
beam() { docker exec a0_app dawarich rpc "IO.puts($1)" 2>/dev/null | tail -1; }
before="$(beam ':erlang.memory(:total)')"
(while :; do beam ':erlang.memory(:total)'; sleep 1; done) >"$work/mem" &
sampler=$!
curl -fsS -D "$work/dl-headers" -o "$work/dl" http://127.0.0.1:3900/a2-stream.bin
tr -d '\r' <"$work/dl-headers" | grep -qi '^content-length: 209715200$' || fail "the download lost its length"
if tr -d '\r' <"$work/dl-headers" | grep -qi '^transfer-encoding'; then fail "the download was re-chunked"; fi
[ "$(sha "$work/dl")" = "$expected" ] || fail "the download was corrupted"
[ "$(curl -fsS -r 100-199 -o /dev/null -w '%{http_code} %{size_download}' http://127.0.0.1:3900/a2-stream.bin)" = "206 100" ] \
  || fail "a range request did not come through"

head -c 209715200 /dev/urandom >"$work/up.bin"
md5="$(openssl md5 -binary "$work/up.bin" | base64)"
url="$(docker exec a0_app bin/rails runner '
  blob = ActiveStorage::Blob.create_before_direct_upload!(filename: "a2.bin", byte_size: 209715200, checksum: ARGV[0], content_type: "application/octet-stream")
  ActiveStorage::Current.url_options = { protocol: "http", host: "127.0.0.1", port: 3900 }
  puts blob.service_url_for_direct_upload' "$md5" 2>/dev/null | tail -1)"
case "$url" in http://127.0.0.1:3900/rails/active_storage/disk/*) ;; *) fail "no direct-upload URL" ;; esac
[ "$(curl -sS -o /dev/null -w '%{http_code}' -T "$work/up.bin" -H 'Content-Type: application/octet-stream' "$url")" = 204 ] \
  || fail "the 200 MiB upload did not arrive intact"
kill "$sampler"
after="$(beam ':erlang.memory(:total)')"
peak="$(sort -n "$work/mem" | tail -1)"
echo "BEAM memory before / peak during / after 200 MiB each way: $before / $peak / $after bytes"
[ $((peak - before)) -lt 67108864 ] || fail "the BEAM grew by 64 MiB or more during the transfers: the proxy buffers bodies"

docker exec a0_app bin/rails runner 'User.find_or_create_by!(email: "a2-smoke@example.com") { |u| u.password = "phoenix-a2-smoke-password" }' >/dev/null 2>&1 \
  || fail "cannot create the smoke user"
net="$(docker inspect -f '{{range $name, $_ := .NetworkSettings.Networks}}{{$name}} {{end}}' a0_app | cut -d' ' -f1)"
sign_in='jar="$(mktemp)"
  token="$(curl -fsS -c "$jar" -H "Host: 127.0.0.1:3900" "$1/users/sign_in" | sed -n "s/.*name=\"authenticity_token\" value=\"\([^\"]*\)\".*/\1/p" | head -1)"
  if [ -n "$2" ]; then xff="X-Forwarded-For: $2"; else xff="X-A2-Smoke: 1"; fi
  if [ -n "${3:-}" ]; then nominated="Connection: $3"; else nominated="X-A2-Smoke-Connection: 1"; fi
  curl -sS -o /dev/null -w "%{http_code}" -b "$jar" -c "$jar" -H "Host: 127.0.0.1:3900" -H "$xff" -H "$nominated" \
    --data-urlencode "authenticity_token=$token" --data-urlencode "user[email]=a2-smoke@example.com" \
    --data-urlencode "user[password]=phoenix-a2-smoke-password" "$1/users/sign_in"'
signed_in_from() {
  case "$(sh -c "$sign_in" _ http://127.0.0.1:3900 '')" in 302|303) ;; *) fail "direct sign-in failed ($1)" ;; esac
  case "$(docker run --rm --network "$net" --entrypoint sh "$IMAGE" -c "$sign_in" _ http://dawarich_app:3000 203.0.113.7)" in
    302|303) ;; *) fail "sign-in through a proxy container failed ($1)" ;;
  esac
  docker exec a0_app bin/rails runner 'u = User.find_by!(email: "a2-smoke@example.com"); puts "#{u.last_sign_in_ip} #{u.current_sign_in_ip}"' 2>/dev/null | tail -1
}
signed_in_from proxied >"$work/ips-proxied"
read -r direct_ip proxied_client <"$work/ips-proxied"
[ "$proxied_client" = 203.0.113.7 ] || fail "behind Phoenix, a trusted proxy's X-Forwarded-For client was recorded as $proxied_client"
case "$direct_ip" in ''|127.0.0.1|::ffff:*|::1) fail "behind Phoenix, a direct client was recorded as '$direct_ip'" ;; esac
case "$(docker run --rm --network "$net" --entrypoint sh "$IMAGE" -c "$sign_in" _ http://dawarich_app:3000 203.0.113.8 X-Forwarded-For)" in
  302|303) ;; *) fail "sign-in through a proxy container with Connection: X-Forwarded-For failed" ;;
esac
nominated_client="$(docker exec a0_app bin/rails runner 'puts User.find_by!(email: "a2-smoke@example.com").current_sign_in_ip' 2>/dev/null | tail -1)"
[ "$nominated_client" = 203.0.113.8 ] \
  || fail "behind Phoenix, a client that named X-Forwarded-For in Connection was recorded as $nominated_client"

docker exec a0_app sh -c 'head -c 1048576 /dev/urandom >/var/app/public/a2-1m.bin'
bench() {
  docker exec a0_app sh -c '
    : >/tmp/a2-urls; i=0
    while [ $i -lt "$3" ]; do printf "url = \"%s\"\noutput = \"/dev/null\"\n" "$1" >>/tmp/a2-urls; i=$((i + 1)); done
    s=$(date +%s%N)
    curl -s --parallel --parallel-max "$2" -H "Host: 127.0.0.1:3900" -w "%{time_total}\n" -K /tmp/a2-urls | sort -n >/tmp/a2-times
    ms=$((($(date +%s%N) - s) / 1000000))
    awk -v ms="$ms" "{ t[NR] = \$1 } END { printf \"%.2f %.2f %d\\n\", t[int(NR * 0.5)] * 1000, t[int(NR * 0.99)] * 1000, NR * 1000 / ms }" /tmp/a2-times' _ "$1" "$2" "$3"
}
latency() {
  set -- "$1" "$2" $(bench "http://127.0.0.1:3000$1" 1 500) $(bench "http://127.0.0.1:$upstream$1" 1 500)
  echo "$1 one request at a time — proxied p50 $3 ms, p99 $4 ms; direct p50 $6 ms, p99 $7 ms"
  awk -v a="$3" -v b="$6" -v m="$2" 'BEGIN { exit !(a <= b + m) }' \
    || fail "$1 misses the single-request budget (p50 +$2 ms)"
}
saturation() {
  mode="${3:-}"
  quota="$(docker exec a0_app sh -c 'read q p </sys/fs/cgroup/cpu.max; [ "$q" = max ] || [ "$q" -ge $((p * $(nproc))) ] && echo none || echo set')"
  floor="${2:-$([ "$quota" = none ] && echo 85 || echo 65)}"
  ratios=""
  for pair in 1 2 3 4 5; do
    if [ $((pair % 2)) = 1 ]; then
      set -- "$1" $(bench "http://127.0.0.1:3000$1" 8 2000) $(bench "http://127.0.0.1:$upstream$1" 8 2000)
    else
      set -- "$1" $(bench "http://127.0.0.1:$upstream$1" 8 2000) $(bench "http://127.0.0.1:3000$1" 8 2000)
      set -- "$1" "$5" "$6" "$7" "$2" "$3" "$4"
    fi
    echo "$1 at concurrency 8, pair $pair — proxied p50 $2 ms, p99 $3 ms, $4 req/s; direct p50 $5 ms, p99 $6 ms, $7 req/s"
    ratios="$ratios $(awk -v e="$4" -v f="$7" 'BEGIN { printf "%.1f", e * 100 / f }')"
  done
  median="$(printf '%s\n' $ratios | sort -n | sed -n 3p)"
  echo "$1 proxied/direct over five interleaved pairs:$ratios % — median $median % (floor $floor %)"
  if [ "$mode" = unconstrained-only ] && [ "$quota" = set ]; then
    echo "$1: under a CPU quota this budget is noise-bound; reported, not enforced"
    return 0
  fi
  awk -v m="$median" -v r="$floor" 'BEGIN { exit !(m >= r) }' \
    || fail "$1 misses the saturation budget ($floor % of direct throughput, median of five pairs)"
}
latency /api/v1/health 1
latency /a2-1m.bin 2
saturation /api/v1/health
saturation /a2-1m.bin 90 unconstrained-only

if [ "${SOAK_MINUTES:-0}" -gt 0 ]; then
  procs0="$(beam ':erlang.system_info(:process_count)')"
  mem0="$(beam ':erlang.memory(:total)')"
  docker exec a0_app sh -c 'jar="$(mktemp)"
    token="$(curl -fsS -c "$jar" http://127.0.0.1:3000/users/sign_in | sed -n "s/.*name=\"authenticity_token\" value=\"\([^\"]*\)\".*/\1/p" | head -1)"
    curl -sS -o /dev/null -b "$jar" -c "$jar" --data-urlencode "authenticity_token=$token" \
      --data-urlencode "user[email]=a2-smoke@example.com" --data-urlencode "user[password]=phoenix-a2-smoke-password" \
      http://127.0.0.1:3000/users/sign_in
    cookie="$(awk -F "\t" "NF == 7 { printf \"%s%s=%s\", s, \$6, \$7; s = \"; \" }" "$jar")"
    i=0
    while [ $i -lt 100 ]; do
      curl -s -N -m $(($1 * 60)) -H "Cookie: $cookie" -H "Origin: http://127.0.0.1:3000" ws://127.0.0.1:3000/cable -o /dev/null &
      i=$((i + 1))
    done
    end=$(($(date +%s) + $1 * 60))
    while [ "$(date +%s)" -lt "$end" ]; do curl -s -o /dev/null -b "$jar" http://127.0.0.1:3000/api/v1/health; sleep 0.2; done
    wait' _ "$SOAK_MINUTES" &
  soak=$!
  sleep 60
  open="$(docker exec a0_app sh -c 'cat /proc/net/tcp /proc/net/tcp6' | awk '$4 == "01" && $2 ~ /:0BB8$/' | wc -l | tr -d ' ')"
  echo "soak: $(beam ':erlang.system_info(:process_count)') processes, $(beam ':erlang.memory(:total)') bytes with $open connections open on 3000"
  [ "$open" -ge 100 ] || fail "the soak's cable connections did not stay open"
  wait "$soak"
  sleep 30
  procs1="$(beam ':erlang.system_info(:process_count)')"
  mem1="$(beam ':erlang.memory(:total)')"
  echo "soak: before $procs0 processes / $mem0 bytes, after $procs1 / $mem1"
  [ "$procs1" -le $((procs0 + 20)) ] || fail "processes did not return to their baseline after the soak"
  [ "$mem1" -le $((mem0 + mem0 / 5)) ] || fail "memory did not return to its baseline after the soak"
fi

echo "docker stats: $(docker stats --no-stream --format '{{.Name}} {{.MemUsage}} {{.CPUPerc}}' a0_app)"
start="$(date +%s)"
$compose stop dawarich_app
[ $(($(date +%s) - start)) -lt 10 ] || fail "the web container took 10 s or more to stop"
[ "$(docker inspect -f '{{.State.ExitCode}}' a0_app)" = "0" ] || fail "unclean stop"
docker logs a0_app 2>&1 | tail -20 | grep -qi 'goodbye' || fail "puma did not shut down gracefully"

printf 'services:\n  dawarich_app:\n    environment:\n      DAWARICH_PROXY: "off"\n' >"$override_off"
docker compose -p phoenix-a0 -f docker/docker-compose.yml -f "$override" -f "$override_off" up -d dawarich_app
tries=0
until [ "$(docker inspect -f '{{.State.Health.Status}}' a0_app)" = "healthy" ]; do
  tries=$((tries + 1))
  [ "$tries" -lt $((WAIT / 5)) ] || fail "app not healthy with DAWARICH_PROXY=off"
  sleep 5
done
docker logs a0_app 2>&1 | grep -q 'Phoenix proxy off (DAWARICH_PROXY=off)' || fail "the kill switch was not honoured"
docker exec a0_app ps -o comm= -p 1 | grep -q beam || fail "PID 1 is not the BEAM under the kill switch"
signed_in_from "kill switch" >"$work/ips-direct"
diff "$work/ips-direct" "$work/ips-proxied" || fail "Rails records other client addresses behind Phoenix than behind nothing"
$compose stop dawarich_app
[ "$(docker inspect -f '{{.State.ExitCode}}' a0_app)" = "0" ] || fail "unclean stop under the kill switch"
tries=0
until docker logs a0_sidekiq 2>&1 | grep -q 'Running in ruby'; do
  tries=$((tries + 1))
  [ "$tries" -lt "$WAIT" ] || fail "sidekiq did not finish booting"
  sleep 1
done
$compose stop dawarich_sidekiq
[ "$(docker inspect -f '{{.State.ExitCode}}' a0_sidekiq)" = "0" ] || fail "sidekiq unclean stop"
echo "image smoke: ok"
