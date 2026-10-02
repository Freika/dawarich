defmodule Dawarich.Auth.RememberCookieTest do
  use ExUnit.Case, async: true

  alias Dawarich.Auth.RememberCookie
  alias Dawarich.{Accounts, RailsCookies}

  @fixture Jason.decode!(File.read!(Path.expand("../../fixtures/rails_cookies.json", __DIR__)))
  @secret @fixture["rails_test_secret"]
  @payload @fixture["expected_remember"]
  @now DateTime.from_iso8601(@fixture["now"]) |> elem(1)
  @expiry DateTime.add(@now, @fixture["remember_for_seconds"])

  test "matches the independently captured Rails signed remember cookie" do
    cookie = RememberCookie.sign(@payload, @secret, @expiry)
    assert URI.decode_www_form(cookie) == URI.decode_www_form(@fixture["remember_cookie"])
    assert {:ok, @payload} == RailsCookies.verify(cookie, "remember_user_token", @secret, @now)
  end

  test "rejects replay at the expiry boundary" do
    cookie = RememberCookie.sign(@payload, @secret, @expiry)

    assert {:ok, @payload} ==
             RailsCookies.verify(
               cookie,
               "remember_user_token",
               @secret,
               DateTime.add(@expiry, -1)
             )

    assert :error == RailsCookies.verify(cookie, "remember_user_token", @secret, @expiry)
  end

  test "binds cookie purpose and signing secret" do
    cookie = RememberCookie.sign(@payload, @secret, @expiry)
    assert :error == RailsCookies.verify(cookie, "_dawarich_session", @secret, @now)
    assert :error == RailsCookies.verify(cookie, "remember_user_token", "wrong-secret", @now)
  end

  test "rejects a changed signed message" do
    cookie = RememberCookie.sign(@payload, @secret, @expiry)
    [data, digest] = cookie |> URI.decode_www_form() |> String.split("--")
    altered = "A" <> binary_part(data, 1, byte_size(data) - 1) <> "--" <> digest
    assert :error == RailsCookies.verify(altered, "remember_user_token", @secret, @now)
  end

  test "the generated_at stamp keeps Ruby's decimal Float#to_s form on a whole second" do
    assert Accounts.remember_generated_at(~U[2026-10-01 16:00:00.000000Z]) == "1790870400.0"
    assert Accounts.remember_generated_at(~U[2026-10-01 16:00:00.073300Z]) == "1790870400.0733"

    hash = String.duplicate("a", 60)
    user = %{id: 7, encrypted_password: hash, remember_created_at: ~U[2026-10-01 15:00:00Z]}
    stamp = Accounts.remember_generated_at(~U[2026-10-01 16:00:00.000000Z])

    assert Accounts.remembered?(
             user,
             [[7], binary_part(hash, 0, 29), stamp],
             ~U[2026-10-01 16:00:01Z]
           )
  end
end
