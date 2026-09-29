defmodule Dawarich.SubscriptionTokenTest do
  use ExUnit.Case, async: false

  @fixture "test/fixtures/subscription_token.json" |> File.read!() |> Jason.decode!()
  @external_resource "test/fixtures/subscription_token.json"

  test "the token is byte-for-byte the one Rails' JWT gem builds" do
    previous = System.get_env("JWT_SECRET_KEY")
    System.put_env("JWT_SECRET_KEY", @fixture["secret"])

    on_exit(fn ->
      if previous,
        do: System.put_env("JWT_SECRET_KEY", previous),
        else: System.delete_env("JWT_SECRET_KEY")
    end)

    user = %{id: @fixture["user_id"], email: @fixture["email"]}

    [header, payload, signature] =
      Dawarich.SubscriptionToken.generate(
        user,
        DateTime.from_unix!(@fixture["now"]),
        @fixture["jti"]
      )
      |> String.split(".")

    decode = &Base.url_decode64!(&1, padding: false)
    assert decode.(header) == @fixture["header"]
    assert decode.(payload) == @fixture["payload"]
    assert Base.encode16(decode.(signature), case: :lower) == @fixture["signature"]
  end
end
