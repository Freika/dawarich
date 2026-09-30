defmodule Dawarich.Wave5bFixturesTest do
  use ExUnit.Case, async: false

  alias Dawarich.ScratchRepo
  alias Dawarich.Wave5bFixtures

  @allowed_public_hosts ~w(photon.komoot.io app.chibigeo.com api.geoapify.com us1.locationiq.com)
  @point_sql "SELECT lock_version, timestamp, ST_AsText(lonlat) FROM points WHERE id = $1"
  @place_sql "SELECT latitude::text, longitude::text, ST_AsText(lonlat) FROM places WHERE id = $1"
  @visit_sql "SELECT floor(extract(epoch FROM started_at))::bigint, " <>
               "floor(extract(epoch FROM ended_at))::bigint FROM visits WHERE id = $1"

  setup do
    unless ScratchRepo.query!("SELECT to_regclass('public.users') IS NOT NULL", [], log: false).rows ==
             [[true]] do
      Dawarich.ScratchCase.recreate_public!()

      ScratchRepo.query!(Dawarich.ReleaseMigrator.baseline_sql(), [],
        query_type: :text,
        log: false
      )
    end

    truncate!()
    :ok
  end

  test "every fixture loads into the scratch database" do
    for path <- Wave5bFixtures.names() do
      raw = File.read!(path)
      refute raw =~ "Johannisthal", "#{path} must never contain Johannisthal"
      fixture = Wave5bFixtures.read!(path)
      assert_synthetic_hosts!(path, fixture)

      assert is_binary(fixture["postgis_build"]) and fixture["postgis_build"] != "",
             "#{path} is missing postgis_build"

      for input <- inputs(fixture) do
        row_counts = Wave5bFixtures.load_input!(ScratchRepo, input)

        for table <- Wave5bFixtures.tables(), Map.has_key?(input, table) do
          assert row_counts[table] == length(input[table]),
                 "#{path}: #{table} row count mismatch (loaded #{row_counts[table]}, fixture has #{length(input[table])})"
        end

        assert_round_trip!(path, input)
        truncate!()
      end
    end
  end

  defp inputs(fixture) do
    cases = for %{"input" => input} <- fixture["cases"] || [], do: input
    [fixture["input"] || %{} | cases]
  end

  defp assert_round_trip!(path, input) do
    for row <- input["points"] || [] do
      assert loaded(@point_sql, row["id"]) == [
               row["lock_version"] || 0,
               row["timestamp"],
               row["lonlat_wkt"]
             ],
             "#{path}: point #{row["id"]} did not load as recorded"
    end

    for %{"latitude" => lat} = row <- input["places"] || [] do
      assert loaded(@place_sql, row["id"]) == [lat, row["longitude"], row["lonlat_wkt"]],
             "#{path}: place #{row["id"]} did not load as recorded"
    end

    for row <- input["visits"] || [] do
      assert loaded(@visit_sql, row["id"]) == [row["started_at"], row["ended_at"]],
             "#{path}: visit #{row["id"]} did not load as recorded"
    end
  end

  defp loaded(sql, id), do: ScratchRepo.query!(sql, [id], log: false).rows |> List.first()

  defp assert_synthetic_hosts!(path, fixture) do
    for host <- hosts(fixture) do
      assert synthetic?(host), "#{path}: non-synthetic host #{inspect(host)}"
    end
  end

  defp hosts(%{} = map) do
    Enum.flat_map(map, fn
      {"host", host} when is_binary(host) ->
        [host |> String.split("/") |> hd() |> String.split(":") |> hd()]

      {"url", url} when is_binary(url) ->
        [URI.parse(url).host]

      {_key, value} ->
        hosts(value)
    end)
  end

  defp hosts(list) when is_list(list), do: Enum.flat_map(list, &hosts/1)
  defp hosts(_value), do: []

  defp synthetic?(host) do
    host == "example.test" or String.ends_with?(host, ".example.test") or
      host in @allowed_public_hosts
  end

  defp truncate! do
    ScratchRepo.query!(
      "TRUNCATE #{Enum.join(Wave5bFixtures.tables(), ", ")} RESTART IDENTITY CASCADE",
      [],
      log: false
    )
  end
end
