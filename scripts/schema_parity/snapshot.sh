#!/bin/sh
set -eu
release="$1"
root="$(cd "$(dirname "$0")/../.." && pwd)"
. "$root/scripts/schema_parity/lib.sh"
out_dir="$snapshots"
provenance="$out_dir/provenance.tsv"
mkdir -p "$out_dir"
snapshot_of "$release" >/dev/null 2>&1 && { echo "skip $release"; exit 0; }

db="sp_$(echo "$release" | tr . _)"
tmp_sql="$out_dir/.$release.tmp.sql"
run_log="$out_dir/.$release.run.log"
pulled=""
cleanup() {
  rm -f "$tmp_sql" "$tmp_sql.gz" "$run_log" "$provenance.tmp"
  [ -z "$pulled" ] || docker rmi "freikin/dawarich:$pulled" >/dev/null 2>&1 || true
  docker exec "$db_container" dropdb -U postgres --if-exists "$db" >/dev/null 2>&1 || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
docker exec "$db_container" dropdb -U postgres --if-exists "$db"

hub_digest() {
  response="$(curl -s --max-time 30 -w '\n%{http_code}' "https://hub.docker.com/v2/repositories/freikin/dawarich/tags/$1")" || {
    echo "could not reach Docker Hub tags API for $1" >&2
    exit 1
  }
  http_code="$(printf '%s\n' "$response" | tail -n 1)"
  case "$http_code" in
    200) printf '%s\n' "$response" | sed '$d' | ruby -rjson -e 'puts JSON.parse($stdin.read)["digest"] || abort("no digest in the Docker Hub tags API answer")' ;;
    404) echo none ;;
    *)
      echo "unexpected Docker Hub tags API status $http_code for $1" >&2
      exit 1
      ;;
  esac
}

migrate_in_image() {
  docker run --rm --pull never --network "$network" --entrypoint "" \
    -e RAILS_ENV=production -e SECRET_KEY_BASE="$(od -An -N64 -tx1 /dev/urandom | tr -d ' \n')" \
    -e DATABASE_HOST="$db_container" -e DATABASE_PORT=5432 -e DATABASE_USERNAME=postgres -e DATABASE_PASSWORD=parity \
    -e DATABASE_NAME="$db" -e DATABASE_URL="$db_adapter://postgres:parity@$db_container:5432/$db" \
    -e SCHEMA=/tmp/schema_parity_no_fast_path.rb \
    -e OTP_ENCRYPTION_PRIMARY_KEY=schema-parity-primary-key \
    -e OTP_ENCRYPTION_DETERMINISTIC_KEY=schema-parity-deterministic-key \
    -e OTP_ENCRYPTION_KEY_DERIVATION_SALT=schema-parity-key-derivation-salt \
    -e REDIS_URL=redis://$redis_container:6379 -e APPLICATION_HOSTS=localhost -e SELF_HOSTED=true \
    "freikin/dawarich:$1" sh -c "
      bundle exec rails $2 db:migrate &&
      if bundle exec rake -T 2>/dev/null | grep -q 'rake data:migrate '; then
        bundle exec rails db:seed && bundle exec rake data:migrate
      fi" > "$run_log" 2>&1
}

failure_reason() {
  awk '
    $1 == "==" && $4 == "migrating" { mig = $2 " " substr($3, 1, length($3) - 1) }
    $1 == "==" && $4 == "migrated" && mig == $2 " " substr($3, 1, length($3) - 1) { mig = "" }
    /aborted!$/ && abort == "" { getline; abort = $0 }
    /^Caused by:$/ { getline; cause = $0 }
    END {
      why = (cause != "") ? cause : abort
      if (why == "") why = "no error message in the container output"
      if (mig != "") why = mig ": " why
      print why
    }' "$run_log"
}

previous_state() {
  ruby -rjson -e '
    states = JSON.parse(File.read(ARGV[0]))["states"].map { _1["first_release"] }
    index = states.index(ARGV[1])
    puts states[index - 1] if index&.positive?' "$root/db/release_migrations.json" "$release"
}

later_releases_of_state() {
  ruby -rjson -e '
    state = JSON.parse(File.read(ARGV[0]))["states"].find { _1["first_release"] == ARGV[1] }
    puts state["releases"].drop(1) if state' "$root/db/release_migrations.json" "$release"
}

pull_image() {
  retries="${SNAPSHOT_PULL_RETRIES:-12}"
  wait_s="${SNAPSHOT_PULL_WAIT:-360}"
  attempt=0
  while :; do
    pulled="$1"
    pull_out="$(docker pull "freikin/dawarich:$1" 2>&1)" && break
    if ! printf '%s' "$pull_out" | grep -qiE 'toomanyrequests|429 too many requests|pull rate limit'; then
      printf '%s\n' "$pull_out" >&2
      echo "docker pull failed for $1" >&2
      exit 1
    fi
    attempt=$((attempt + 1))
    if [ "$attempt" -ge "$retries" ]; then
      echo "pull rate-limited for $1" >&2
      exit 1
    fi
    sleep "$wait_s"
  done
}

build_with_image() {
  image="$1"
  upgraded_from=""
  attempt_failure=""
  pull_image "$image"
  db_adapter="$(docker run --rm --pull never --entrypoint sh "freikin/dawarich:$image" -c "grep -m1 '  adapter:' config/database.yml" | awk '{print $2}')"
  docker exec "$db_container" dropdb -U postgres --if-exists "$db"
  if migrate_in_image "$image" db:create; then
    built=yes
  else
    attempt_failure="from an empty database: $(failure_reason)"
  fi
  cat "$run_log"

  if [ -z "$built" ]; then
    prev="$(previous_state)"
    prev_snapshot=""
    [ -z "$prev" ] || prev_snapshot="$(snapshot_of "$prev" 2>/dev/null)" || true
    if [ -n "$prev_snapshot" ]; then
      echo "$image cannot migrate $attempt_failure; upgrading $(basename "$prev_snapshot") with the $image image instead" >&2
      docker exec "$db_container" dropdb -U postgres --if-exists "$db"
      docker exec "$db_container" createdb -U postgres "$db"
      gunzip -c "$prev_snapshot" > "$tmp_sql"
      docker exec -i "$db_container" psql -U postgres -q -v ON_ERROR_STOP=1 -d "$db" < "$tmp_sql" >/dev/null
      if migrate_in_image "$image" ""; then
        built=yes
        upgraded_from="$prev"
      else
        attempt_failure="$attempt_failure; upgrading $(basename "$prev_snapshot"): $(failure_reason)"
      fi
      cat "$run_log"
    fi
  fi

  docker rmi "freikin/dawarich:$image" >/dev/null 2>&1 || true
  pulled=""
}

built=""
had_image=""
failure=""
digest=none
siblings="$(later_releases_of_state)"
for candidate in $release $siblings; do
  digest="$(hub_digest "$candidate")"
  if [ "$digest" = none ]; then
    failure="${failure:+$failure; }$candidate: no image on Docker Hub"
    continue
  fi
  had_image=yes
  [ "$candidate" = "$release" ] || echo "$release: trying $candidate, a later release of the same state" >&2
  build_with_image "$candidate"
  [ -n "$built" ] && break
  failure="${failure:+$failure; }$candidate: $attempt_failure"
done

if [ -n "$built" ]; then
  method=image
  kind=image
  [ "$image" = "$release" ] || kind="$kind-sibling"
  [ -z "$upgraded_from" ] || kind="$kind-upgrade"
  [ -z "$failure" ] || echo "$release: $failure; state built with the $image image${upgraded_from:+, upgraded from $upgraded_from}" >&2
elif [ -n "$had_image" ]; then
  echo "migration failed for $release (image): $failure" >&2
  exit 1
else
  method=replay
  kind=replay
  image=-
  upgraded_from=""
  digest=-
  docker exec "$db_container" createdb -U postgres "$db"
  (cd "$root" && env $rails_env DATABASE_NAME="$db" bin/rails runner scripts/schema_parity/replay.rb "$release")
fi

dump_snapshot "$db" "$tmp_sql"
gzip -9 "$tmp_sql"
mv "$tmp_sql.gz" "$out_dir/$release.$method.sql.gz"

row="$(printf '%s\t%s\t%s\t%s\t%s\t%s' "$release" "$release.$method.sql.gz" "$kind" "$image" "${upgraded_from:--}" "$digest")"
[ -s "$provenance" ] || printf 'state\tfile\tmethod\timage\tupgraded_from\thub_digest\n' > "$provenance"
awk -F '\t' -v state="$release" -v row="$row" '
  $1 == state { print row; done = 1; next }
  { print }
  END { if (!done) print row }' "$provenance" > "$provenance.tmp"
mv "$provenance.tmp" "$provenance"

echo "ok $release $kind image=$image upgraded_from=${upgraded_from:--}"
