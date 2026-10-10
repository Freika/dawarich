defmodule Dawarich.SubscriptionTokenTest do
  use ExUnit.Case, async: false

  @fixture "test/fixtures/subscription_token.json" |> File.read!() |> Jason.decode!()
  @external_resource "test/fixtures/subscription_token.json"

  test "trial checkout options match Rails ordered JWT claims" do
    previous = System.get_env("JWT_SECRET_KEY")
    System.put_env("JWT_SECRET_KEY", "a10-checkout-synthetic-signing-phrase-not-for-production")

    on_exit(fn ->
      if previous,
        do: System.put_env("JWT_SECRET_KEY", previous),
        else: System.delete_env("JWT_SECRET_KEY")
    end)

    for {name, opts} <- [
          {"upgrade_pro_annual", [plan: "pro", interval: "annual"]},
          {"upgrade_lite_monthly", [plan: "lite", interval: "monthly"]},
          {"upgrade_invalid", [plan: nil, interval: ""]},
          {"resume_cloud_pending", [variant: "reverse_trial"]}
        ] do
      state = Jason.decode!(File.read!("test/fixtures/trial_home/#{name}.json"))
      oracle = state["jwt"]
      user = %{id: state["user"]["id"], email: state["user"]["email"]}
      now = state["now"] |> DateTime.from_iso8601() |> elem(1)

      [header, payload, signature] =
        Dawarich.SubscriptionToken.generate(user, now, oracle["payload"]["jti"], opts)
        |> String.split(".")

      assert Base.url_decode64!(header, padding: false) == oracle["header_json"]
      assert Base.url_decode64!(payload, padding: false) == oracle["payload_json"]

      assert Base.encode16(Base.url_decode64!(signature, padding: false), case: :lower) ==
               oracle["signature_hex"]
    end
  end

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
