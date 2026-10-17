defmodule Dawarich.MapApi.Fog do
  @moduledoc false
  alias Dawarich.{RailsTime, Repo, RubyInteger}
  alias Dawarich.Tiles.Http

  def fetch(user, params) do
    required = Enum.find(~w(start_date end_date), &(not Http.present?(params[&1])))

    if required do
      {:error, 400, "Missing required parameter: #{required}"}
    else
      RailsTime.with_zone(user.timezone, fn ->
        with {:ok, from} <- Http.strict_timestamp(params["start_date"]),
             {:ok, to} <- Http.strict_timestamp(params["end_date"]) do
          collect(user, from, to)
        else
          _ -> {:error, 400, "Invalid date format"}
        end
      end)
    end
  rescue
    _ -> {:error, 500, "Failed to generate hexagon grid"}
  end

  defp collect(user, from, to) do
    [[first, last]] =
      Repo.query!(
        "SELECT extract(year FROM a)::int*100+extract(month FROM a)::int,extract(year FROM b)::int*100+extract(month FROM b)::int FROM (SELECT to_timestamp($1) AS a,to_timestamp($2) AS b)x",
        [from, to]
      ).rows

    cutoff = Http.window(user)

    plan =
      if cutoff,
        do:
          "AND year*100+month >= (extract(year FROM to_timestamp(#{cutoff}))::int*100+extract(month FROM to_timestamp(#{cutoff}))::int)",
        else: ""

    rows =
      Repo.query!(
        "SELECT h3_hex_ids FROM stats WHERE user_id=$1 AND year*100+month BETWEEN $2 AND $3 #{plan} ORDER BY id",
        [user.id, first, last]
      ).rows

    ids =
      Enum.flat_map(rows, fn
        [cells] when is_list(cells) ->
          Enum.flat_map(cells, fn
            [index, _count, earliest, latest] ->
              if present?(index) and overlaps?(earliest, latest, from, to), do: [index], else: []

            [index | _] ->
              if present?(index), do: [index], else: []

            _ ->
              []
          end)

        _ ->
          []
      end)
      |> Enum.uniq()

    {:ok, %{"h3_indexes" => ids, "metadata" => %{"count" => length(ids)}}}
  end

  defp present?(v), do: v not in [nil, false, ""] and v != [] and v != %{}

  defp overlaps?(earliest, latest, from, to),
    do:
      not present?(earliest) or not present?(latest) or
        (RubyInteger.to_i(earliest) <= to and RubyInteger.to_i(latest) >= from)
end
