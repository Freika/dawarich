defmodule Dawarich.GeocodingCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  alias Dawarich.Geocoding.{FakeHttp, HookRepo}
  alias Dawarich.{Redis, ScratchRepo, Wave5bFixtures}

  @vars ~w(PHOTON_API_HOST PHOTON_API_KEY PHOTON_API_USE_HTTPS GEOAPIFY_API_KEY NOMINATIM_API_HOST
           NOMINATIM_API_KEY NOMINATIM_API_USE_HTTPS LOCATIONIQ_API_KEY REVERSE_GEOCODING_RPS STORE_GEODATA)
  @dir "test/fixtures/geocoding"
  @point_sql "SELECT id, city, country_name, country_id, geodata::text, reverse_geocoded_at IS NOT NULL, " <>
               "lock_version FROM points ORDER BY id"

  using do
    quote do
      use Dawarich.JobsCase
      import Dawarich.GeocodingCase
      alias Dawarich.Geocoding.{FakeHttp, HookRepo}
      alias Dawarich.Wave5bFixtures

      setup do: Dawarich.GeocodingCase.setup!()
    end
  end

  def setup! do
    for var <- @vars,
        do: System.get_env(var) in [nil, ""] || raise("#{var} must be blank for geocoding tests")

    ScratchRepo.query!(
      "TRUNCATE points, places, instance_settings, countries RESTART IDENTITY CASCADE",
      [],
      log: false
    )

    ExUnit.Callbacks.start_supervised!(FakeHttp)
    ExUnit.Callbacks.start_supervised!(hd(Redis.child_specs()))
    ExUnit.Callbacks.start_supervised!(hd(Redis.cache_child_specs()))
    {:ok, "OK"} = Redis.command(["FLUSHDB"])
    {:ok, "OK"} = Redis.cache_command(["FLUSHDB"])
    HookRepo.clear_hook()
    ExUnit.Callbacks.on_exit(&HookRepo.clear_hook/0)
    :ok
  end

  def fixture(name), do: Wave5bFixtures.read!(Path.join(@dir, name <> ".json"))
  def fixture_names, do: @dir |> Path.join("*.json") |> Path.wildcard() |> Enum.sort()

  def load!(name), do: Wave5bFixtures.load!(ScratchRepo, Path.join(@dir, name <> ".json")).fixture

  def stub_requests!(requests) do
    Enum.each(requests, fn
      %{"url" => url, "timeout" => true} -> FakeHttp.stub_error(url, :timeout)
      %{"url" => url, "status" => status, "body" => body} -> FakeHttp.stub(url, status, body)
    end)
  end

  def config_from(%{"enabled" => false} = c),
    do: %{enabled: false, store_geodata: c["store_geodata"]}

  def config_from(c) do
    %{
      enabled: true,
      source: String.to_atom(c["source"]),
      provider: String.to_atom(c["provider"]),
      host: c["host"],
      api_key: c["api_key"],
      use_https: c["use_https"],
      rps: c["rps"],
      store_geodata: c["store_geodata"]
    }
  end

  def comparable(%{enabled: false} = c),
    do: %{"enabled" => false, "store_geodata" => c.store_geodata}

  def comparable(c) do
    %{
      "enabled" => true,
      "source" => Atom.to_string(c.source),
      "provider" => Atom.to_string(c.provider),
      "host" => c.host,
      "api_key" => c.api_key,
      "use_https" => c.use_https,
      "rps" => c.rps,
      "store_geodata" => c.store_geodata
    }
  end

  def fixture_config(%{"enabled" => false} = c), do: Map.take(c, ["enabled", "store_geodata"])
  def fixture_config(c), do: c

  def points do
    for [id, city, country, country_id, geodata, geocoded, version] <- rows(@point_sql),
        do: [id, city, country, country_id, geodata, geocoded, version]
  end

  def expected_points(points) do
    for p <- points,
        do: [
          p["id"],
          p["city"],
          p["country_name"],
          p["country_id"],
          p["geodata"],
          p["reverse_geocoded_at"] != nil,
          p["lock_version"]
        ]
  end

  def kinds do
    for [kind, payload] <- rows("SELECT kind, payload FROM phoenix.rails_commands ORDER BY id"),
        do: %{"kind" => kind, "payload" => payload}
  end

  def geocoded_days do
    {:ok, members} = Redis.command(["ZRANGE", "stats:geocoded_days:pending", "0", "-1"])
    Enum.sort(members)
  end

  def cache_entries do
    {:ok, keys} = Redis.cache_command(["KEYS", "*"])

    keys
    |> Enum.sort()
    |> Enum.map(fn key ->
      %{"key" => key, "value" => elem(Redis.cache_command(["GET", key]), 1)}
    end)
  end

  def clear_limiter! do
    {:ok, keys} = Redis.command(["KEYS", "geocoding:rate_limit:*"])
    Enum.each(keys, &Redis.command(["DEL", &1]))
  end

  def dedupe_key(id), do: "geocode:enq:Point:#{id}"

  def dedupe_key?(id), do: Redis.command(["EXISTS", dedupe_key(id)]) == {:ok, 1}

  defp rows(sql), do: ScratchRepo.query!(sql, [], log: false).rows
end
