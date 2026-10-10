defmodule DawarichWeb.RateLimit.RulesTest do
  use ExUnit.Case, async: true

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.Test.RateLimitCorpus
  alias DawarichWeb.RateLimit.Rules

  defp corpus, do: RateLimitCorpus.corpus()

  test "the throttle table equals Rails' in declaration order, limits and periods" do
    phoenix =
      for {name, limit, period, _methods, _path, _needs, _key} <- Rules.throttles(),
          do: %{"name" => name, "limit" => Rules.limit(limit, %{plan: nil}), "period" => period}

    retained = Enum.reject(corpus()["throttles"], &(&1["name"] == "admin/flipper"))
    assert phoenix == retained
    assert Rules.plan_limits() == corpus()["plan_limits"]
    assert corpus()["blocklists"] == ["api/auth/oversized_json_body"]
  end

  test "keys and TTLs are rack-attack's: window number, name and the normalized discriminator" do
    now = corpus()["now"]
    increment = fn _key, _ttl -> {:ok, 1} end

    assert {:pass, [{key, ttl}], nil} =
             Rules.evaluate([{"logins/ip", 20, 60, " 203.0.113.9 "}], now, increment)

    assert key == "rack::attack:#{div(now, 60)}:logins/ip:203.0.113.9"
    assert ttl == 60 - rem(now, 60) + 1
  end

  test "counting stops at the first throttle over its limit" do
    increment = fn key, _ttl ->
      send(self(), {:counted, key})
      {:ok, if(String.contains?(key, ":first:"), do: 6, else: 1)}
    end

    assert {:throttled, [{"rack::attack:16:first:x", 21}], %{limit: 5, count: 6, period: 60}} =
             Rules.evaluate([{"first", 5, 60, "x"}, {"second", 5, 60, "x"}], 1_000, increment)

    refute_received {:counted, "rack::attack:16:second:x"}
  end

  test "the discriminator normalizer is rack-attack's to_s.strip.downcase for every recorded value" do
    for v <- corpus()["normalized"],
        do: assert(Rules.normalize(v["input"]) == v["output"], inspect(v))
  end

  test "presence is ActiveSupport's present? for every recorded value" do
    for v <- corpus()["present"],
        do: assert(Ruby.present?(v["input"]) == v["present"], inspect(v))
  end

  test "the oversized-body blocklist covers the sign-in JSON paths, the API ones only on Cloud" do
    base = %{
      method: "POST",
      json: true,
      content_length: 16_385,
      self_hosted: false,
      throttle_path: "/users/sign_in"
    }

    for {path, self_hosted, blocked} <- [
          {"/users/sign_in", true, true},
          {"/users/sign_in", false, true},
          {"/api/v1/auth/login", false, true},
          {"/api/v1/auth/login", true, false},
          {"/api/v1/auth/otp_challenge", true, false},
          {"/users", false, false}
        ],
        do:
          assert(
            Rules.blocked?(%{base | throttle_path: path, self_hosted: self_hosted}) == blocked,
            path
          )

    refute Rules.blocked?(%{base | content_length: 16_384})
    refute Rules.blocked?(%{base | json: false})
    refute Rules.blocked?(%{base | method: "PUT"})
  end
end
