defmodule Dawarich.Auth.Api.ChallengeVerifyTest do
  use ExUnit.Case, async: false
  alias Dawarich.Auth.Api.ChallengeToken
  alias Dawarich.{Redis, Repo}
  alias Dawarich.Test.ApiJwtFixture

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    for spec <- Redis.cache_child_specs(), do: start_supervised!(spec)
    :ok
  end

  test "OTP token verification mirrors admitted expiry age and signature boundaries without effects" do
    rows = ApiJwtFixture.vectors()

    admitted = ~w(explicit unset empty blank padded age300 future-iat)
    before = Repo.query!("SELECT to_jsonb(u) FROM users u ORDER BY id", [], log: false).rows

    for row <- rows, row["name"] != "unavailable" do
      context = %{
        env: %{"JWT_SECRET_KEY" => row["secret"]},
        rails_secret: nil,
        clock: fn -> DateTime.from_unix!(row["now"]) end
      }

      result = ChallengeToken.verify(row["token"], context)

      if row["name"] in admitted do
        assert {:ok, claims} = result
        assert claims == row["claims"], row["name"]

        assert {:ok, nil} =
                 Redis.cache_command(["GET", "otp_challenge:consumed:" <> claims["jti"]])
      else
        assert match?({:replay, _}, result), row["name"]
      end
    end

    row = Enum.find(rows, &(&1["name"] == "explicit"))
    assert {:replay, _} = ChallengeToken.verify(row["token"], %{env: %{}, rails_secret: nil})

    assert before ==
             Repo.query!("SELECT to_jsonb(u) FROM users u ORDER BY id", [], log: false).rows
  end
end
