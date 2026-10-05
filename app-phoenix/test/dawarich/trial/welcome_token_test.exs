defmodule Dawarich.Trial.WelcomeTokenTest do
  use ExUnit.Case, async: true
  alias Dawarich.Trial.WelcomeToken
  @secret "synthetic-a10b-welcome-signing-phrase"
  @now 1_791_108_000

  test "decimal string coercion follows Ruby digit separators whitespace and suffixes" do
    for {value, expected} <- [
          {"1_791_109_800", 1_791_109_800},
          {" \t\r\n\v\f+01_2suffix", 12},
          {"-0_1", -1},
          {"1__2", 1},
          {"1_", 1},
          {"0x12", 0},
          {"1" <> <<0>> <> "2", 1},
          {" 1_2", 0},
          {"invalid", 0}
        ] do
      assert WelcomeToken.integer(value) == {:ok, expected}
    end
  end

  test "verifies HS256 purpose required expiry and source claim semantics" do
    assert Code.ensure_loaded?(WelcomeToken), "welcome token decoder must exist"

    payload = %{
      "user_id" => 13_001,
      "purpose" => "trial_welcome",
      "exp" => @now + 1800,
      "jti" => "a10b-token"
    }

    assert {:ok, ^payload} = WelcomeToken.decode(token(payload), @secret, @now)

    for bad <- [
          nil,
          "",
          "not-a-jwt",
          "a.b.c",
          "a.b.c.d",
          "%%%.e30.x",
          token(payload, "different-synthetic-key"),
          token(payload, @secret, %{"alg" => "HS512"}),
          token(payload, @secret, %{"alg" => "none"}),
          token(payload, @secret, %{}),
          token(payload, @secret, []),
          token([])
        ] do
      assert {:error, :invalid} = WelcomeToken.decode(bad, @secret, @now)
    end

    for changes <- [
          %{"purpose" => "checkout"},
          %{"purpose" => nil},
          %{"exp" => @now},
          %{"exp" => @now - 1},
          %{"exp" => "invalid"},
          %{"exp" => nil}
        ] do
      assert {:error, :invalid} =
               WelcomeToken.decode(token(Map.merge(payload, changes)), @secret, @now)
    end

    assert {:error, :invalid} =
             WelcomeToken.decode(token(Map.delete(payload, "exp")), @secret, @now)

    assert {:error, :invalid} =
             WelcomeToken.decode(token(Map.put(payload, "nbf", @now + 1)), @secret, @now)

    assert {:ok, _} = WelcomeToken.decode(token(Map.put(payload, "nbf", @now)), @secret, @now)

    assert {:ok, _} = WelcomeToken.decode(token(%{payload | "exp" => @now + 1}), @secret, @now)

    for exp <- [
          (@now + 1800) * 1.0,
          Integer.to_string(@now + 1800),
          Integer.to_string(@now + 1800) <> "suffix"
        ] do
      assert {:ok, _} = WelcomeToken.decode(token(%{payload | "exp" => exp}), @secret, @now)
    end

    for {jti, expected} <- [
          {nil, ""},
          {" ", " "},
          {%{}, "{}"},
          {[], "[]"},
          {false, "false"},
          {42, "42"}
        ] do
      assert {:ok, decoded} = WelcomeToken.decode(token(%{payload | "jti" => jti}), @secret, @now)
      assert decoded["jti"] == expected
    end

    assert {:ok, decoded} = WelcomeToken.decode(token(Map.delete(payload, "jti")), @secret, @now)
    assert decoded["jti"] == ""
    assert {:handoff, :configuration} = WelcomeToken.decode(token(payload), nil, @now)
  end

  test "does not add status email issuer or audience requirements" do
    assert Code.ensure_loaded?(WelcomeToken), "welcome token decoder must exist"
    minimal = %{"purpose" => "trial_welcome", "exp" => @now + 1800}

    for extra <- [
          %{},
          %{"status" => "inactive", "email" => nil, "iss" => "optional", "aud" => ["optional"]},
          %{"user_id" => "not-an-id", "jti" => "scalar"}
        ] do
      assert {:ok, decoded} = WelcomeToken.decode(token(Map.merge(minimal, extra)), @secret, @now)
      assert Map.drop(decoded, ["jti"]) == Map.drop(Map.merge(minimal, extra), ["jti"])
    end

    for exp <- [true, [], %{}] do
      assert {:handoff, :claims} =
               WelcomeToken.decode(token(Map.put(minimal, "exp", exp)), @secret, @now)
    end

    assert {:handoff, :claims} =
             WelcomeToken.decode(
               token(Map.put(minimal, "jti", %{"nested" => "unsupported"})),
               @secret,
               @now
             )
  end

  defp token(payload, secret \\ @secret, header \\ %{"alg" => "HS256"}) do
    input = encode(Jason.encode!(header)) <> "." <> encode(Jason.encode!(payload))
    input <> "." <> encode(:crypto.mac(:hmac, :sha256, secret, input))
  end

  defp encode(value), do: Base.url_encode64(value, padding: false)
end
