defmodule Dawarich.Cache.Readers do
  @moduledoc false

  alias Dawarich.{Redis, Stats}
  alias Dawarich.Stats.Toponyms

  def summary(user, rows, opts \\ []) do
    signature = :crypto.hash(:sha256, :erlang.term_to_binary(Enum.sort(rows)))
    toponyms = Enum.flat_map(rows, & &1.toponyms)

    for {suffix, name, compute} <- [
          {"countries_visited", :countries_visited, fn -> Toponyms.countries(toponyms) end},
          {"cities_visited", :cities_visited, fn -> Toponyms.cities(toponyms) end},
          {"total_distance", :total_distance,
           fn -> rows |> Enum.map(& &1.distance) |> Enum.sum() end}
        ],
        into: %{} do
      key = "dawarich/user_#{user}_#{suffix}"
      value = fetch(key, signature, 86_400, compute, opts)
      {name, value}
    end
  end

  def yearly(id, year, digest, _stats, compute, opts) do
    value = compute.()

    if value do
      key = Dawarich.Insights.Details.Digests.key(id, year, value["updated_at"])

      case read(key) do
        %{digest: ^digest} when value == digest ->
          digest

        _ ->
          write(key, %{digest: value}, 3600, opts)
          value
      end
    end
  end

  def tracked_months(repo, id, opts \\ []) do
    months =
      Dawarich.RailsTime.with_zone(repo, "Etc/UTC", fn -> Stats.TrackedMonths.call(repo, id) end)
      |> Enum.map(fn row -> %{"year" => row.year, "months" => row.months} end)

    signature = :crypto.hash(:sha256, :erlang.term_to_binary(months))
    fetch("dawarich/user_#{id}_years_tracked", signature, 86_400, fn -> months end, opts)
  end

  def warm(repo, id, opts) do
    if repo.query!("SELECT id FROM users WHERE id=$1 AND deleted_at IS NULL", [id]).rows != [] do
      result =
        repo.query!("SELECT distance,toponyms FROM stats WHERE user_id=$1 ORDER BY id", [id])

      rows =
        for [distance, toponyms] <- result.rows,
            do: %{distance: distance, toponyms: Toponyms.sanitize(toponyms)}

      summary(id, rows, Keyword.put(opts, :strict, true))

      tracked_months(repo, id, Keyword.put(opts, :strict, true))
      now = opts[:now] || DateTime.utc_now()
      counts = Stats.PointCounts.fetch(id, true, now, repo: repo, cache_repo: repo)
      match_write!(write("dawarich/user_#{id}_points_geocoded_stats", counts, 86_400, opts))
    end

    :ok
  end

  def warm_digests(repo, id, opts) do
    now = opts[:now] || DateTime.utc_now()
    zone = opts[:ambient_zone] || System.get_env("TIME_ZONE", "Europe/Berlin")

    result =
      repo.query!(
        "SELECT d.*,d.travel_patterns::text AS _rails_patterns FROM digests d JOIN users u ON u.id=d.user_id " <>
          "WHERE u.deleted_at IS NULL AND d.user_id=$1 AND d.period_type=1 AND d.year IN " <>
          "(SELECT DISTINCT year FROM stats WHERE user_id=$1 AND year<EXTRACT(year FROM ($2::timestamptz AT TIME ZONE $3)) ORDER BY year DESC LIMIT 2)",
        [id, now, Dawarich.TimeZoneName.to_iana(zone)]
      )

    for row <- result.rows do
      {raw, digest} = Map.new(Enum.zip(result.columns, row)) |> Map.pop("_rails_patterns")
      digest = Map.put(digest, "_rails_json", %{"travel_patterns" => raw})
      key = Dawarich.Insights.Details.Digests.key(id, digest["year"], digest["updated_at"])
      match_write!(write(key, %{digest: digest}, 3600, opts))
    end

    :ok
  end

  defp fetch(key, signature, ttl, compute, opts) do
    case read(key) do
      %{signature: ^signature, value: value} ->
        value

      _ ->
        value = compute.()
        result = write(key, %{signature: signature, value: value}, ttl, opts)
        if opts[:strict], do: match_write!(result)
        value
    end
  end

  defp read(key) do
    case Redis.cache_command(["GET", "phoenix/" <> key]) do
      {:ok, <<"DW1", value::binary>>} -> :erlang.binary_to_term(value, [:safe])
      _ -> nil
    end
  rescue
    ArgumentError -> nil
  end

  defp write(key, value, ttl, opts) do
    if hook = opts[:before_warm_write],
      do: hook.(String.replace(key, ~r/^dawarich\/user_\d+_/, ""))

    bytes = "DW1" <> :erlang.term_to_binary(value)
    Redis.cache_command(["SET", "phoenix/" <> key, bytes, "EX", to_string(ttl)])
  end

  defp match_write!({:ok, "OK"}), do: :ok
  defp match_write!(error), do: raise("Native cache warming failed: #{inspect(elem(error, 0))}")
end
