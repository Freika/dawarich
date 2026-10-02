defmodule Dawarich.RailsCookiesTest do
  use ExUnit.Case, async: true

  alias Dawarich.RailsCookies

  @fixture "test/fixtures/rails_cookies.json" |> File.read!() |> Jason.decode!()
  @secret @fixture["rails_test_secret"]
  @now @fixture["now"] |> DateTime.from_iso8601() |> elem(1)
  @other "phoenix-a2-some-other-secret-not-for-production"

  defp tamper(value) do
    <<head::binary-size(4), char, tail::binary>> = URI.decode_www_form(value)
    URI.encode_www_form(head <> <<if(char == ?A, do: ?B, else: ?A)>> <> tail)
  end

  test "decrypts the session cookie Rails set at sign-in" do
    assert RailsCookies.decrypt(@fixture["session_cookie"], "_dawarich_session", @secret, @now) ==
             {:ok, @fixture["expected_session"]}
  end

  test "verifies the remember-me cookie Devise set at sign-in" do
    assert RailsCookies.verify(@fixture["remember_cookie"], "remember_user_token", @secret, @now) ==
             {:ok, @fixture["expected_remember"]}
  end

  test "refuses a value encrypted for another cookie name" do
    assert RailsCookies.decrypt(
             @fixture["other_purpose_cookie"],
             "_dawarich_session",
             @secret,
             @now
           ) == :error

    assert {:ok, "unlocked"} =
             RailsCookies.decrypt(
               @fixture["other_purpose_cookie"],
               "shared_link_1",
               @secret,
               @now
             )
  end

  test "refuses the cookies under another secret" do
    assert RailsCookies.decrypt(@fixture["session_cookie"], "_dawarich_session", @other, @now) ==
             :error

    assert RailsCookies.verify(@fixture["remember_cookie"], "remember_user_token", @other, @now) ==
             :error
  end

  test "refuses a tampered cookie" do
    assert RailsCookies.decrypt(
             tamper(@fixture["session_cookie"]),
             "_dawarich_session",
             @secret,
             @now
           ) == :error

    assert RailsCookies.verify(
             tamper(@fixture["remember_cookie"]),
             "remember_user_token",
             @secret,
             @now
           ) == :error
  end

  test "refuses a remember-me cookie once the expiry Rails embedded in it has passed" do
    later = DateTime.add(@now, 15 * 24 * 3600)

    assert RailsCookies.verify(@fixture["remember_cookie"], "remember_user_token", @secret, later) ==
             :error
  end

  test "refuses garbage without raising" do
    for value <- ["", "a--b", "%%%", "YQ==--YQ==--YQ==", "--", "----", String.duplicate("-", 10)] do
      assert RailsCookies.decrypt(value, "_dawarich_session", @secret, @now) == :error
      assert RailsCookies.verify(value, "remember_user_token", @secret, @now) == :error
    end
  end

  test "refuses a session cookie whose GCM tag or IV is not the length Rails writes" do
    [data, iv, tag] = @fixture["session_cookie"] |> URI.decode_www_form() |> String.split("--")
    {:ok, raw_tag} = Base.decode64(tag)
    {:ok, raw_iv} = Base.decode64(iv)

    shaped = fn parts -> parts |> Enum.join("--") |> URI.encode_www_form() end

    for size <- [1, 8, 15] do
      short = raw_tag |> binary_part(0, size) |> Base.encode64()
      cookie = shaped.([data, iv, short])

      assert RailsCookies.decrypt(cookie, "_dawarich_session", @secret, @now) == :error,
             "tag #{size}"
    end

    for bad_iv <- [binary_part(raw_iv, 0, 11), raw_iv <> <<0>>] do
      cookie = shaped.([data, Base.encode64(bad_iv), tag])
      assert RailsCookies.decrypt(cookie, "_dawarich_session", @secret, @now) == :error
    end
  end
end
