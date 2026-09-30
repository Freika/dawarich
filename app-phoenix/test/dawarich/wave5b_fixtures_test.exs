defmodule Dawarich.Wave5bFixturesTest do
  use ExUnit.Case, async: false

  alias Dawarich.ScratchRepo
  alias Dawarich.Wave5bFixtures

  @tables ~w(users points places areas visits imports tags taggings instance_settings countries)

  # The four providers' own default public hosts, plus ChibiGeo: its
  # host-specific rate-limit metering (Geocoding::Providers.chibigeo?) is
  # gated on this exact literal hostname, so the fixture that proves it
  # cannot use a synthetic stand-in.
  @allowed_public_hosts ~w(
    photon.komoot.io
    app.chibigeo.com
    api.geoapify.com
    nominatim.openstreetmap.org
    us1.locationiq.com
  )

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
      assert_synthetic_hosts!(path)

      %{fixture: fixture, row_counts: row_counts} = Wave5bFixtures.load!(ScratchRepo, path)

      assert is_binary(fixture["postgis_build"]) and fixture["postgis_build"] != "",
             "#{path} is missing postgis_build"

      input = fixture["input"] || %{}

      for table <- @tables, Map.has_key?(input, table) do
        assert row_counts[table] == length(input[table]),
               "#{path}: #{table} row count mismatch (loaded #{row_counts[table]}, fixture has #{length(input[table])})"
      end

      truncate!()
    end
  end

  defp assert_synthetic_hosts!(path) do
    fixture = Wave5bFixtures.read!(path)

    hosts =
      (config_hosts(fixture) ++ request_hosts(fixture))
      |> Enum.reject(&is_nil/1)

    for host <- hosts do
      assert synthetic?(host), "#{path}: non-synthetic host #{inspect(host)}"
    end
  end

  defp config_hosts(fixture) do
    case get_in(fixture, ["config", "host"]) do
      nil -> []
      host -> [host |> String.split("/") |> List.first()]
    end
  end

  defp request_hosts(fixture) do
    fixture
    |> Map.get("requests", [])
    |> List.wrap()
    |> Enum.map(fn request -> request["url"] |> URI.parse() |> Map.get(:host) end)
  end

  defp synthetic?(host) do
    host == "example.test" or String.ends_with?(host, ".example.test") or
      host in @allowed_public_hosts
  end

  defp truncate! do
    ScratchRepo.query!("TRUNCATE #{Enum.join(@tables, ", ")} RESTART IDENTITY CASCADE", [],
      log: false
    )
  end
end
