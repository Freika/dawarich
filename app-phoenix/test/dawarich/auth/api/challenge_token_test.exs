defmodule Dawarich.Auth.Api.ChallengeTokenTest do
  use ExUnit.Case, async: true
  alias Dawarich.Auth.Api.ChallengeToken
  alias Dawarich.Test.ApiJwtFixture

  defp vectors do
    ApiJwtFixture.vectors()
  end

  defp context(row) do
    %{
      env: %{
        "JWT_SECRET_KEY" => row["context"]["jwt_secret_key"],
        "AUTH_JWT_SECRET_KEY" => row["context"]["auth_jwt_secret_key"]
      },
      rails_secret: row["context"]["rails_secret"],
      clock: fn -> DateTime.from_unix!(row["now"]) end,
      jti: fn -> row["jti"] end
    }
  end

  test "OTP challenge issuance matches source HS256 claims secret fallback and TTL" do
    row = Enum.find(vectors(), &(&1["name"] == "explicit"))
    assert row["secret"] == ApiJwtFixture.secret("jwt")
    assert row["now"] == DateTime.to_unix(ApiJwtFixture.now())
    assert row["user_id"] == ApiJwtFixture.user_id()
    assert {:ok, token} = ChallengeToken.issue(row["user_id"], context(row))
    assert token == row["token"]
    [head, body, _] = String.split(token, ".")
    assert decode(head) == %{"alg" => "HS256"}
    claims = decode(body)
    assert claims == row["claims"]
    assert claims["purpose"] == "otp_challenge"
    assert claims["exp"] - claims["iat"] == 300
    assert Map.keys(claims) |> Enum.sort() == ~w(exp iat jti purpose user_id)
    live = Map.drop(context(row), [:clock, :jti])
    before_issuance = DateTime.to_unix(DateTime.utc_now())
    assert {:ok, first} = ChallengeToken.issue(row["user_id"], live)
    assert {:ok, second} = ChallengeToken.issue(row["user_id"], live)
    after_issuance = DateTime.to_unix(DateTime.utc_now())
    assert first != second
    a = first |> String.split(".") |> Enum.at(1) |> decode()
    b = second |> String.split(".") |> Enum.at(1) |> decode()
    assert {:ok, _} = Ecto.UUID.cast(a["jti"])
    assert a["jti"] != b["jti"]

    for issued <- [a, b] do
      assert issued["iat"] in before_issuance..after_issuance
      assert issued["exp"] - issued["iat"] == 300
    end
  end

  test "OTP secrets match the Rails matrix and unavailable fallback hands back" do
    for row <- vectors(), row["source"] == "issuer" or row["name"] == "unavailable" do
      if row["expected"] != "unavailable" do
        assert row["context"]["rails_secret"] == ApiJwtFixture.secret("fallback")
      end

      assert row["context"]["auth_jwt_secret_key"] == ApiJwtFixture.secret("mobile")
      result = ChallengeToken.issue(row["user_id"], context(row))

      if row["expected"] == "unavailable" do
        assert {:replay, :secret} = result
      else
        assert {:ok, token} = result
        assert token == row["token"], row["name"]
        assert {:ok, secret} = ChallengeToken.secret(context(row))
        assert secret == row["secret"], row["name"]
        refute secret == row["context"]["auth_jwt_secret_key"]
      end
    end
  end

  defp decode(segment), do: segment |> Base.url_decode64!(padding: false) |> Jason.decode!()
end
