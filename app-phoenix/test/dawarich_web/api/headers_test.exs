defmodule DawarichWeb.Api.HeadersTest do
  use ExUnit.Case, async: true

  alias DawarichWeb.Api.Headers

  test "the X-Dawarich pair names the version and whether a key resolved to a user" do
    assert Headers.dawarich(true, "1.2.3") ==
             [
               {"x-dawarich-response", "Hey, I'm alive and authenticated!"},
               {"x-dawarich-version", "1.2.3"}
             ]

    assert Headers.dawarich(false, "1.2.3") ==
             [{"x-dawarich-response", "Hey, I'm alive!"}, {"x-dawarich-version", "1.2.3"}]
  end

  test "rate-limit headers follow ApiController#set_rate_limit_headers" do
    base = %{self_hosted: false, authenticated: true, now: 1_790_000_123}

    assert Headers.rate_limit(Map.put(base, :throttle, %{limit: 1000, count: 17, period: 3600})) ==
             [
               {"x-ratelimit-limit", "1000"},
               {"x-ratelimit-remaining", "983"},
               {"x-ratelimit-reset", "1790002800"}
             ]

    assert [_, {"x-ratelimit-remaining", "0"}, _] =
             Headers.rate_limit(Map.put(base, :throttle, %{limit: 200, count: 201, period: 3600}))

    assert [_, _, {"x-ratelimit-reset", "1790002800"}] =
             Headers.rate_limit(
               %{base | now: 1_789_999_200}
               |> Map.put(:throttle, %{limit: 200, count: 1, period: 3600})
             )
  end

  test "no rate-limit headers self-hosted, without a user or without throttle data" do
    throttle = %{limit: 1000, count: 1, period: 3600}

    assert Headers.rate_limit(%{
             self_hosted: true,
             authenticated: true,
             throttle: throttle,
             now: 1
           }) == []

    assert Headers.rate_limit(%{
             self_hosted: false,
             authenticated: false,
             throttle: throttle,
             now: 1
           }) == []

    assert Headers.rate_limit(%{self_hosted: false, authenticated: true, throttle: nil, now: 1}) ==
             []
  end
end
