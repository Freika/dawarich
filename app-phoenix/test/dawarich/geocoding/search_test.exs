defmodule Dawarich.Geocoding.SearchTest do
  use Dawarich.GeocodingCase, async: false

  alias Dawarich.Geocoding.{Query, RateLimiter, ResponseCache, Search}
  alias Dawarich.{Redis, TtlCache}

  @errors %{
    "Geocoder::OverQueryLimitError" => :over_query_limit,
    "Geocoder::ServiceUnavailable" => :service_unavailable,
    "Geocoder::ResponseParseError" => :response_parse_error,
    "Geocoder::LookupTimeout" => :timeout,
    "Geocoder::InvalidApiKey" => :invalid_api_key,
    "Geocoder::RequestDenied" => :request_denied,
    "Geocoder::InvalidRequest" => :invalid_request,
    "TypeError" => :unexpected_document
  }

  test "status errors are raised before caching" do
    assert run("photon_429") == [{:error, :over_query_limit}]
    assert cache_entries() == []
    assert run("photon_503") == [{:error, :service_unavailable}]
    assert cache_entries() == []
  end

  test "a 200 invalid-JSON body is cached, then a parse error" do
    c = search_case("photon_invalid_json_200")
    [%{"key" => key, "value" => body}] = c["cache"]
    own_key!(key)
    stub_requests!(c["requests"])

    before = System.monotonic_time(:millisecond)
    assert reverse(c) == {:error, :response_parse_error}
    assert cache_entries() == c["cache"]
    after_put = System.monotonic_time(:millisecond)
    assert [{_, ^body, deadline}] = native_entry(key)
    assert deadline in (before + 86_400_000)..(after_put + 86_400_000)
    assert reverse(c) == {:error, :response_parse_error}
    assert length(FakeHttp.requests()) == 1
  end

  test "a cache hit makes no request but takes a slot" do
    c = search_case("photon_cache_hit")
    [%{"key" => key, "value" => value}] = c["cache"]
    own_key!(key)
    ResponseCache.put(key, value)
    stub_requests!(c["requests"])
    config = %{config_from(c["config"]) | rps: 10.0}
    limiter = "geocoding:rate_limit:" <> RateLimiter.key(config)

    assert Search.reverse(config, query(c), []) == {:ok, hd(c["outcomes"])["data"]}
    first = slot(limiter)
    assert Search.reverse(config, query(c), []) == {:ok, hd(c["outcomes"])["data"]}

    assert FakeHttp.requests() == []
    assert slot(limiter) - first == 100_000
  end

  test "provider-specific bodies" do
    assert run("nominatim_bandwidth_text") == [{:error, :over_query_limit}]
    assert run("locationiq_error_1") == [{:error, :invalid_api_key}]
    assert run("locationiq_error_2") == [{:error, :request_denied}]
    assert run("locationiq_error_3") == [{:error, :over_query_limit}]
    assert run("locationiq_error_4") == [{:error, :invalid_request}]
    assert run("geoapify_status_code_500") == [{:error, :invalid_request}]
    assert run("photon_not_feature_collection") == [{:ok, []}]
    assert run("photon_json_array") == [{:error, :unexpected_document}]
  end

  test "every recorded search outcome, request count and cache entry equals Rails'" do
    for c <- fixture("search_outcomes")["cases"] do
      reset!()
      stub_requests!(c["requests"])

      for outcome <- c["outcomes"] do
        before = length(FakeHttp.requests())
        assert {c["name"], reverse(c)} == {c["name"], expected(outcome)}

        assert {c["name"], length(FakeHttp.requests()) - before} ==
                 {c["name"], outcome["requests"]}
      end

      assert {c["name"], cache_entries()} == {c["name"], Enum.sort_by(c["cache"], & &1["key"])}
    end
  end

  test "Rails' documents that are not results" do
    config = %{config_from(search_case("photon_429")["config"]) | host: "p.example.test"}
    url = "https://p.example.test/reverse?lang=en&lat=1.0&lon=2.0"

    for {body, result} <- [
          {"null", {:ok, []}},
          {"false", {:ok, []}},
          {~s("text"), {:ok, []}},
          {"5", {:error, :unexpected_document}},
          {~s({"type":"FeatureCollection","features":false}), {:ok, []}}
        ] do
      reset!()
      FakeHttp.stub(url, 200, body)
      assert {body, Search.reverse(config, {1.0, 2.0}, [])} == {body, result}
    end
  end

  test "a missing host or key returns [] without a slot" do
    for name <- ~w(photon_missing_host geoapify_missing_key) do
      c = search_case(name)
      config = %{config_from(c["config"]) | rps: 10.0}
      assert Search.reverse(config, query(c), []) == {:ok, []}
    end

    assert FakeHttp.requests() == []
    assert Redis.command(["KEYS", "geocoding:rate_limit:*"]) == {:ok, []}
  end

  test "no Redis cache process is needed for a native miss and hit" do
    c = search_case("photon_cache_hit")
    [%{"key" => key, "value" => body}] = c["cache"]
    own_key!(key)
    stub_requests!(c["requests"])

    assert Process.whereis(Dawarich.Redis.Cache) == nil
    assert reverse(c) == {:ok, hd(c["outcomes"])["data"]}
    assert reverse(c) == {:ok, hd(c["outcomes"])["data"]}
    assert length(FakeHttp.requests()) == 1
    assert [{_, ^body, _}] = native_entry(key)
  end

  test "two successful lookups use one HTTP response and the native cache" do
    start_supervised!(hd(Redis.cache_child_specs()))
    assert Redis.cache_command(["FLUSHDB"]) == {:ok, "OK"}
    c = search_case("photon_cache_hit")
    [%{"key" => key, "value" => body}] = c["cache"]
    own_key!(key)
    stub_requests!(c["requests"])

    assert reverse(c) == {:ok, hd(c["outcomes"])["data"]}
    assert reverse(c) == {:ok, hd(c["outcomes"])["data"]}
    assert length(FakeHttp.requests()) == 1
    assert [{_, ^body, _}] = native_entry(key)
    assert Redis.cache_command(["GET", key]) == {:ok, nil}
  end

  test "a cached provider error is decoded again without another request" do
    c = search_case("locationiq_error_1")
    [%{"key" => key, "value" => body}] = c["cache"]
    own_key!(key)
    stub_requests!(c["requests"])

    assert reverse(c) == {:error, :invalid_api_key}
    assert reverse(c) == {:error, :invalid_api_key}
    assert length(FakeHttp.requests()) == 1
    assert [{_, ^body, _}] = native_entry(key)
  end

  test "an empty raw body misses again but empty features hit" do
    config = boundary_config()
    coords = {51.3407, 12.3731}
    {url, key, _} = Query.build(config, coords, [], "9.9.9")
    own_key!(key)
    FakeHttp.stub(url, 200, "")

    for call <- 1..2 do
      assert Search.reverse(config, coords, []) == {:error, :response_parse_error}
      assert length(FakeHttp.requests()) == call
      assert [{_, "", _}] = native_entry(key)
    end

    TtlCache.delete({ResponseCache, key})
    body = ~s({"type":"FeatureCollection","features":[]})
    FakeHttp.stub(url, 200, body)

    assert Search.reverse(config, coords, []) == {:ok, []}
    assert length(FakeHttp.requests()) == 3
    assert Search.reverse(config, coords, []) == {:ok, []}
    assert length(FakeHttp.requests()) == 3
    assert [{_, ^body, _}] = native_entry(key)
    assert cache_entries() == [%{"key" => key, "value" => body}]
  end

  test "noncacheable responses and timeouts are looked up again" do
    config = boundary_config()
    coords = {51.3407, 12.3731}
    {url, key, _} = Query.build(config, coords, [], "9.9.9")
    own_key!(key)
    c = search_case("photon_cache_hit")
    body = hd(c["cache"])["value"]

    cases = [
      {400, {:error, :invalid_request}},
      {401, {:error, :request_denied}},
      {402, {:error, :over_query_limit}},
      {404, {:ok, hd(c["outcomes"])["data"]}},
      {429, {:error, :over_query_limit}},
      {503, {:error, :service_unavailable}},
      {:timeout, {:error, :timeout}}
    ]

    for {status, outcome} <- cases do
      TtlCache.delete({ResponseCache, key})
      before = length(FakeHttp.requests())

      if status == :timeout,
        do: FakeHttp.stub_error(url, :timeout),
        else: FakeHttp.stub(url, status, body)

      for call <- 1..2 do
        assert {status, Search.reverse(config, coords, [])} == {status, outcome}
        assert {status, length(FakeHttp.requests()) - before} == {status, call}
      end

      assert native_entry(key) == []
      assert cache_entries() == []
    end
  end

  test "hits retain the deadline and expiry requests a fresh response" do
    c = search_case("photon_cache_hit")
    [%{"key" => key, "value" => body}] = c["cache"]
    own_key!(key)
    stub_requests!(c["requests"])

    assert reverse(c) == {:ok, hd(c["outcomes"])["data"]}
    assert [{native_key, ^body, deadline}] = native_entry(key)
    assert reverse(c) == {:ok, hd(c["outcomes"])["data"]}
    assert [{^native_key, ^body, ^deadline}] = native_entry(key)
    assert length(FakeHttp.requests()) == 1
    now = System.monotonic_time(:millisecond)
    :ets.insert(TtlCache, {native_key, body, now})

    assert reverse(c) == {:ok, hd(c["outcomes"])["data"]}
    assert length(FakeHttp.requests()) == 2
    assert [{^native_key, ^body, renewed}] = native_entry(key)
    assert renewed > now
  end

  test "existing TtlCache eviction makes geocoding a cold miss" do
    c = search_case("photon_cache_hit")
    key = hd(c["cache"])["key"]
    own_key!(key)
    previous = :ets.tab2list(TtlCache)

    on_exit(fn ->
      :ets.match_delete(TtlCache, {{:a13d_eviction, :_}, :_, :_})
      :ets.insert(TtlCache, previous)
    end)

    stub_requests!(c["requests"])
    assert reverse(c) == {:ok, hd(c["outcomes"])["data"]}
    assert native_entry(key) != []
    assert reverse(c) == {:ok, hd(c["outcomes"])["data"]}
    assert length(FakeHttp.requests()) == 1

    for n <- 1..10_001, do: TtlCache.put({:a13d_eviction, n}, n, 60_000)
    assert :ets.info(TtlCache, :size) <= 10_000
    assert native_entry(key) == []
    assert reverse(c) == {:ok, hd(c["outcomes"])["data"]}
    assert length(FakeHttp.requests()) == 2
  end

  test "cache identity separates hosts coordinates and place options" do
    c = search_case("photon_cache_hit")
    config = config_from(c["config"])
    body = hd(c["cache"])["value"]

    variations = [
      {config, query(c), []},
      {%{config | host: "other.photon.example.test"}, query(c), []},
      {config, {51.3407, 12.3731}, []},
      {config, query(c), [limit: 10, radius: 1, distance_sort: true]}
    ]

    keys =
      for {conf, coords, opts} <- variations do
        {url, key, _} = Query.build(conf, coords, opts, "9.9.9")
        own_key!(key)
        FakeHttp.stub(url, 200, body)
        before = length(FakeHttp.requests())
        assert Search.reverse(conf, coords, opts) == {:ok, hd(c["outcomes"])["data"]}
        assert Search.reverse(conf, coords, opts) == {:ok, hd(c["outcomes"])["data"]}
        assert length(FakeHttp.requests()) - before == 1
        assert [{_, ^body, _}] = native_entry(key)
        key
      end

    assert length(Enum.uniq(keys)) == 4
    assert length(FakeHttp.requests()) == 4
  end

  test "a Rails-warmed Redis body does not warm the native cache" do
    start_supervised!(hd(Redis.cache_child_specs()))
    c = search_case("photon_cache_hit")
    [%{"key" => key, "value" => body}] = c["cache"]
    own_key!(key)
    warmed = ~s({"type":"FeatureCollection","features":[]})
    assert Redis.cache_command(["SET", key, warmed]) == {:ok, "OK"}
    stub_requests!(c["requests"])

    assert reverse(c) == {:ok, hd(c["outcomes"])["data"]}
    assert length(FakeHttp.requests()) == 1
    assert [{_, ^body, _}] = native_entry(key)
    assert Redis.cache_command(["GET", key]) == {:ok, warmed}
  end

  test "clearing geocoding entries preserves unrelated cache entries" do
    key = "https://namespace-clear.example.test/reverse"
    own_key!(key)
    TtlCache.delete(key)
    on_exit(fn -> TtlCache.delete(key) end)
    ResponseCache.put(key, "raw body")
    TtlCache.put(key, :unrelated, 60_000)

    Dawarich.GeocodingCase.clear_response_cache!()

    assert ResponseCache.get(key) == :error
    assert TtlCache.lookup(key) == {:ok, :unrelated}
    assert cache_entries() == []
  end

  test "a disabled configuration makes no request" do
    assert Search.reverse(%{enabled: false, store_geodata: true}, {1.0, 2.0}, []) == {:ok, []}
    assert FakeHttp.requests() == []
  end

  defp run(name) do
    c = search_case(name)
    stub_requests!(c["requests"])
    for _outcome <- c["outcomes"], do: reverse(c)
  end

  defp reverse(c), do: Search.reverse(config_from(c["config"]), query(c), [])

  defp query(%{"query" => [lat, lon]}), do: {lat, lon}

  defp expected(%{"raised" => class}), do: {:error, Map.fetch!(@errors, class)}
  defp expected(%{"data" => data}), do: {:ok, data}

  defp search_case(name),
    do: Enum.find(fixture("search_outcomes")["cases"], &(&1["name"] == name))

  defp slot(key) do
    {:ok, value} = Redis.command(["GET", key])
    String.to_integer(value)
  end

  defp boundary_config, do: config_from(search_case("photon_cache_hit")["config"])

  defp native_entry(key), do: :ets.lookup(TtlCache, {ResponseCache, key})

  defp own_key!(key) do
    TtlCache.delete({ResponseCache, key})
    on_exit(fn -> TtlCache.delete({ResponseCache, key}) end)
  end

  defp reset! do
    clear_response_cache!()
  end
end
