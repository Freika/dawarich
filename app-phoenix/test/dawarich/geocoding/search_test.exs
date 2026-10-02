defmodule Dawarich.Geocoding.SearchTest do
  use Dawarich.GeocodingCase, async: false

  alias Dawarich.Geocoding.{RateLimiter, Search}
  alias Dawarich.Redis

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
    stub_requests!(c["requests"])

    assert reverse(c) == {:error, :response_parse_error}
    assert cache_entries() == c["cache"]
    {:ok, ttl} = Redis.cache_command(["TTL", hd(c["cache"])["key"]])
    assert ttl in 86_390..86_400
    assert reverse(c) == {:error, :response_parse_error}
    assert length(FakeHttp.requests()) == 1
  end

  test "a cache hit makes no request but takes a slot" do
    c = search_case("photon_cache_hit")
    [%{"key" => key, "value" => value}] = c["cache"]
    {:ok, "OK"} = Redis.cache_command(["SET", key, value])
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

  test "a cache outage still looks the result up" do
    c = search_case("photon_cache_hit")
    stub_requests!(c["requests"])
    stop_supervised!(Dawarich.Redis.Cache)

    assert reverse(c) == {:ok, hd(c["outcomes"])["data"]}
    assert length(FakeHttp.requests()) == 1
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

  defp reset! do
    {:ok, "OK"} = Redis.cache_command(["FLUSHDB"])
  end
end
