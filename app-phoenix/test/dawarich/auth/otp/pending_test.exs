defmodule Dawarich.Auth.Otp.PendingTest do
  use ExUnit.Case, async: true
  alias Dawarich.Auth.Otp.Pending

  @source "test/fixtures/auth/otp/requests.json" |> File.read!() |> Jason.decode!()
  @now 1_791_115_200
  @keys ~w(otp_user_id otp_challenge_at otp_failed_attempts otp_remember_me)

  test "pending challenge matches source TTL carry-through and four-key cleanup" do
    assert Code.ensure_loaded?(Pending)
    before = %{"locale" => "en", "_csrf_token" => "synthetic", "otp_failed_attempts" => 3}

    for locale <- ~w(en de fr) do
      oracle = @source["start_#{locale}"]["session"]
      pending = Pending.start(before, oracle["otp_user_id"], "1", @now)
      assert Map.take(pending, @keys) == Map.take(oracle, @keys)

      assert Map.take(pending, ~w(locale _csrf_token)) ==
               before |> Map.take(~w(locale _csrf_token))

      assert Pending.valid(pending, @now) == {:ok, oracle["otp_user_id"], true}
      assert Pending.clear(pending) == Map.drop(before, @keys)
      refute Map.has_key?(pending, "warden.user.user.key")

      for remember <- [nil, "0", "true", true, 1] do
        assert Pending.start(before, oracle["otp_user_id"], remember, @now)["otp_remember_me"] ==
                 false
      end
    end

    for {name, stamp} <- [{"ttl_299", @now - 299}, {"ttl_300", @now - 300}, {"future", @now + 60}] do
      source = @source[name]
      pending = %{"otp_user_id" => source["state"]["id"], "otp_challenge_at" => stamp}

      expected =
        if source["session"]["warden.user.user.key"],
          do: {:ok, source["state"]["id"], false},
          else: :expired

      assert Pending.valid(pending, @now) == expected
    end

    assert Pending.valid(%{}, @now) == :expired
    assert Pending.valid(%{"otp_user_id" => 42}, @now) == :expired
    assert Pending.valid(%{"otp_challenge_at" => @now}, @now) == :expired

    for malformed <- ["1791115200", [], %{}, true, 1.0, 999_999_999_999_999_999] do
      assert Pending.valid(%{"otp_user_id" => 42, "otp_challenge_at" => malformed}, @now) ==
               {:handoff, :pending}
    end

    for malformed <- ["42", [], %{}, false, 42.0] do
      assert Pending.valid(%{"otp_user_id" => malformed, "otp_challenge_at" => @now}, @now) ==
               {:handoff, :pending}
    end

    assert Pending.valid(
             %{"otp_user_id" => 42, "otp_challenge_at" => @now, "otp_remember_me" => "1"},
             @now
           ) ==
             {:handoff, :pending}

    assert Pending.clear(Map.merge(before, Map.new(@keys, &{&1, 1}))) == Map.drop(before, @keys)
  end
end
