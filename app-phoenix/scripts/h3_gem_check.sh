#!/bin/sh
set -eu

points="${1:-1000000}"
seed="${2:-20261003}"
resolutions="${3:-8}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
file="$(mktemp)"
trap 'rm -f "$file"' EXIT

ruby_code=$(cat <<'RUBY'
require 'h3'
count, seed, resolutions, path = ARGV
resolutions = resolutions.split(',').map(&:to_i)
random = Random.new(Integer(seed))
File.open(path, 'w') do |out|
  Integer(count).times do
    lat = (random.rand * 180.0) - 90.0
    lng = (random.rand * 360.0) - 180.0
    cells = resolutions.map { |res| H3.from_geo_coordinates([lat, lng], res).to_s(16) }
    out << format("%016x %016x %s\n", [lat].pack('G').unpack1('Q>'), [lng].pack('G').unpack1('Q>'), cells.join(' '))
  end
end
RUBY
)

elixir_code=$(cat <<'ELIXIR'
res = "H3_CHECK_RES" |> System.fetch_env!() |> String.split(",") |> Enum.map(&String.to_integer/1)

{points, mismatches, examples} =
  "H3_CHECK_FILE"
  |> System.fetch_env!()
  |> File.stream!()
  |> Enum.reduce({0, 0, []}, fn line, {n, bad, seen} ->
    [lat, lng | cells] = String.split(line)
    <<la::float>> = <<String.to_integer(lat, 16)::64>>
    <<lo::float>> = <<String.to_integer(lng, 16)::64>>
    got = Enum.map(res, &Dawarich.H3.hex(Dawarich.H3.from_geo({la, lo}, &1)))
    wrong = for {g, c, r} <- Enum.zip([got, cells, res]), g != c, do: {la, lo, r, c, g}
    {n + 1, bad + length(wrong), Enum.take(seen ++ wrong, 5)}
  end)

IO.puts("h3_gem_check points=#{points} cells=#{points * length(res)} mismatches=#{mismatches}")
Enum.each(examples, &IO.inspect/1)
if mismatches > 0, do: System.halt(1)
ELIXIR
)

cd "$root"
bundle exec ruby -e "$ruby_code" "$points" "$seed" "$resolutions" "$file"

if [ -z "${H3_CHECK_MIX:-}" ] && command -v dawarich >/dev/null 2>&1; then
  H3_CHECK_FILE="$file" H3_CHECK_RES="$resolutions" \
    DAWARICH_COOKIE_FILE="${DAWARICH_COOKIE_FILE:-$file.cookie}" dawarich eval "$elixir_code"
  rm -f "$file.cookie"
else
  cd app-phoenix
  H3_CHECK_FILE="$file" H3_CHECK_RES="$resolutions" mix run --no-start -e "$elixir_code"
fi
