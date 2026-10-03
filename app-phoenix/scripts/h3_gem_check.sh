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
raise ArgumentError, 'h3_input config: invalid point count' unless /\A[0-9]+\z/.match?(count) && Integer(count, 10).positive?
resolutions = resolutions.split(',', -1).map do |value|
  raise ArgumentError, 'h3_input config: invalid resolution' unless /\A[0-9]+\z/.match?(value) && Integer(value, 10).between?(0, 15)
  Integer(value, 10)
end
raise ArgumentError, 'h3_input config: empty resolutions' if resolutions.empty?
random = Random.new(Integer(seed))
File.open(path, 'w') do |out|
  Integer(count, 10).times do
    lat = (random.rand * 180.0) - 90.0
    lng = (random.rand * 360.0) - 180.0
    cells = resolutions.map { |res| H3.from_geo_coordinates([lat, lng], res).to_s(16) }
    out << format("%016x %016x %s\n", [lat].pack('G').unpack1('Q>'), [lng].pack('G').unpack1('Q>'), cells.join(' '))
  end
end
RUBY
)

elixir_code=$(cat <<'ELIXIR'
fail = fn scope, reason -> raise ArgumentError, "h3_input #{scope}: #{reason}" end
fetch = fn name ->
  case System.fetch_env(name) do
    {:ok, value} -> value
    :error -> fail.("config", "missing #{name}")
  end
end
parse = fn value, kind ->
  unless String.match?(value, ~r/\A[0-9]+\z/), do: fail.("config", "invalid #{kind}")
  String.to_integer(value, 10)
end
requested_points = parse.(fetch.("H3_CHECK_POINTS"), "point count")
if requested_points <= 0, do: fail.("config", "point count must be positive")
res = fetch.("H3_CHECK_RES") |> String.split(",", trim: false) |> Enum.map(fn token ->
  value = parse.(token, "resolution")
  if value < 0 or value > 15, do: fail.("config", "resolution outside 0..15")
  value
end)
if res == [], do: fail.("config", "empty resolutions")
decode = fn token, minimum, maximum, row ->
  unless String.match?(token, ~r/\A[0-9a-f]{16}\z/), do: fail.("row #{row}", "coordinate must be 16 hex digits")
  bits = String.to_integer(token, 16)
  <<_::1, exponent::11, _::52>> = <<bits::64>>
  if exponent == 0x7FF, do: fail.("row #{row}", "coordinate must be finite")
  <<value::float>> = <<bits::64>>
  if value < minimum or value > maximum, do: fail.("row #{row}", "coordinate outside range")
  value
end

{observed_points, observed_cells, mismatches, examples} =
  fetch.("H3_CHECK_FILE")
  |> File.stream!()
  |> Enum.reduce({0, 0, 0, []}, fn line, {n, compared, bad, seen} ->
    row = n + 1
    if n >= requested_points, do: fail.("row #{row}", "excess point")
    tokens = String.split(line)
    if length(tokens) != 2 + length(res), do: fail.("row #{row}", "wrong reference vector length")
    [lat, lng | cells] = tokens
    la = decode.(lat, -90.0, 90.0, row)
    lo = decode.(lng, -180.0, 180.0, row)
    got = Enum.map(res, &Dawarich.H3.hex(Dawarich.H3.from_geo({la, lo}, &1)))
    wrong = for {g, c, r} <- Enum.zip([got, cells, res]), g != c, do: {la, lo, r, c, g}
    {row, compared + length(got), bad + length(wrong), Enum.take(seen ++ wrong, 5)}
  end)

if observed_points != requested_points, do: fail.("points", "observed #{observed_points}, expected #{requested_points}")
if observed_cells != observed_points * length(res), do: fail.("cells", "incomplete comparisons")
IO.puts("h3_gem_check points=#{observed_points} cells=#{observed_cells} mismatches=#{mismatches}")
Enum.each(examples, &IO.inspect/1)
if mismatches > 0, do: System.halt(1)
ELIXIR
)

cd "$root"
bundle exec ruby -e "$ruby_code" "$points" "$seed" "$resolutions" "$file"

if [ -z "${H3_CHECK_MIX:-}" ] && command -v dawarich >/dev/null 2>&1; then
  H3_CHECK_POINTS="$points" H3_CHECK_FILE="$file" H3_CHECK_RES="$resolutions" \
    DAWARICH_COOKIE_FILE="${DAWARICH_COOKIE_FILE:-$file.cookie}" dawarich eval "$elixir_code"
  rm -f "$file.cookie"
else
  cd app-phoenix
  H3_CHECK_POINTS="$points" H3_CHECK_FILE="$file" H3_CHECK_RES="$resolutions" mix run --no-start -e "$elixir_code"
fi
