defmodule Dawarich.Auth.Recovery.TokenTest do
  use ExUnit.Case, async: true
  alias Dawarich.Auth.Recovery.Token
  @secret "phoenix-a2-cookie-fixture-secret-not-for-production"
  @fixture Jason.decode!(
             File.read!(Path.expand("../../../fixtures/auth/recovery/tokens.json", __DIR__))
           )

  test "matches configured Devise column digests and blank values" do
    columns = %{"reset_password_token" => :reset_password_token, "unlock_token" => :unlock_token}
    assert @fixture["iterations"] == 65_536
    assert @fixture["kdf_digest"] == "OpenSSL::Digest::SHA1"

    for row <- @fixture["cases"] do
      assert Token.digest(columns[row["column"]], row["raw"], @secret) == row["digest"]
    end

    refute Token.digest(:unlock_token, nil, @secret)
  end

  test "digests every Rails-issued recovery token to the digest Rails persisted" do
    notifications =
      Path.expand("../../../fixtures/auth/recovery/lifecycle.json", __DIR__)
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("notifications")

    assert length(notifications) >= 9

    for %{"kind" => kind, "raw" => raw, "persisted_digest" => halves} <- notifications do
      column =
        if kind == "unlock_instructions", do: :unlock_token, else: :reset_password_token

      assert Token.digest(column, raw, @secret) == Enum.join(halves)
    end
  end

  test "derives each column key once per secret, as Devise's caching key generator does" do
    owner = self()
    id = {__MODULE__, make_ref()}

    :telemetry.attach(
      id,
      [:dawarich, :auth, :recovery, :token_key],
      fn _event, _measurements, %{column: column}, _config ->
        if self() == owner, do: send(owner, {:derived, column})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(id) end)
    secret = "token-key-cache-#{System.unique_integer([:positive])}"
    key = :crypto.pbkdf2_hmac(:sha, secret, "Devise reset_password_token", 65_536, 64)
    expected = :crypto.mac(:hmac, :sha256, key, "raw") |> Base.encode16(case: :lower)

    assert Token.digest(:reset_password_token, "raw", secret) == expected
    assert Token.digest(:reset_password_token, "raw", secret) == expected
    assert Token.digest(:unlock_token, "raw", secret) != expected
    assert_received {:derived, :reset_password_token}
    assert_received {:derived, :unlock_token}
    refute_received {:derived, _}
  end

  test "raw tokens preserve Devise length, alphabet substitutions and randomness" do
    values = for _ <- 1..20, do: Token.raw()
    assert length(Enum.uniq(values)) == 20
    assert Enum.all?(values, &(byte_size(&1) == 20 and Regex.match?(~r/\A[A-Za-z0-9_-]+\z/, &1)))
    refute Enum.any?(values, &String.contains?(&1, ["l", "I", "O", "0"]))
  end
end
