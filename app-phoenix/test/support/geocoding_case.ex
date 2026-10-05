defmodule Dawarich.GeocodingCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  alias Dawarich.Geocoding.{FakeHttp, HookRepo, ResponseCache}
  alias Dawarich.{Redis, ScratchRepo, TtlCache, Wave5bFixtures}

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

    ExUnit.Callbacks.start_supervised!(FakeHttp)
    ExUnit.Callbacks.start_supervised!(hd(Redis.child_specs()))
    {:ok, "OK"} = Redis.command(["FLUSHDB"])
    clear_response_cache!()
    HookRepo.clear_hook()

    ExUnit.Callbacks.on_exit(fn ->
      clear_response_cache!()
      HookRepo.clear_hook()
    end)

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

  def geocoded_days,
    do:
      "SELECT member FROM phoenix.stats_geocoded_days" |> rows() |> List.flatten() |> Enum.sort()

  def cache_entries do
    TtlCache
    |> :ets.match_object({{ResponseCache, :_}, :_, :_})
    |> Enum.flat_map(fn {{ResponseCache, key}, _, _} ->
      case TtlCache.lookup({ResponseCache, key}) do
        {:ok, body} -> [%{"key" => key, "value" => body}]
        :error -> []
      end
    end)
    |> Enum.sort_by(& &1["key"])
  end

  def clear_response_cache!, do: :ets.match_delete(TtlCache, {{ResponseCache, :_}, :_, :_})

  def clear_limiter! do
    {:ok, keys} = Redis.command(["KEYS", "geocoding:rate_limit:*"])
    Enum.each(keys, &Redis.command(["DEL", &1]))
  end

  def with_rails_rounding_cases(body) do
    added = %{
      "extent" => [12.373100000000003, 51.339800000000004, 12.373200000000002, 51.3397],
      "distance" => 1500.0
    }

    body
    |> Jason.decode!()
    |> Map.update!("features", fn features ->
      Enum.map(features, fn feature ->
        Map.update!(feature, "properties", &Map.merge(&1, added))
      end)
    end)
    |> Jason.encode!()
  end

  def dedupe_key(id), do: "geocode:enq:Point:#{id}"

  def dedupe_key?(id),
    do:
      ScratchRepo.query!(
        "SELECT 1 FROM phoenix.once_claims WHERE key = $1 AND expires_at > statement_timestamp()",
        [dedupe_key(id)],
        log: false
      ).num_rows == 1

  defp rows(sql), do: ScratchRepo.query!(sql, [], log: false).rows
end
