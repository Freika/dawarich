defmodule Dawarich.Trial.WelcomeClaimTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.Trial.WelcomeClaim
  alias Dawarich.LockRace

  @now 1_791_108_000

  test "PG welcome claims retain key coercion ttl floor and expiry without Redis" do
    for jti <- ["a10b-claim-floor", "Grüße", <<"nul", 0, "jti">>] do
      assert :claimed = WelcomeClaim.claim(jti, @now + 10, @now, ScratchRepo)
      key = key(jti)

      assert [[^key, seconds]] =
               rows(
                 "SELECT key, extract(epoch FROM expires_at - statement_timestamp())::float8 FROM phoenix.once_claims WHERE key=$1",
                 [key]
               )

      assert seconds > 59 and seconds <= 60

      assert [[false]] =
               rows("SELECT key = $1 FROM phoenix.once_claims WHERE key=$2", [
                 "trial_welcome:consumed:" <> String.replace(jti, <<0>>, ""),
                 key
               ])

      rows(
        "UPDATE phoenix.once_claims SET expires_at=statement_timestamp()-interval '1 second' WHERE key=$1",
        [key]
      )

      assert :claimed = WelcomeClaim.claim(jti, Integer.to_string(@now + 30), @now, ScratchRepo)
    end

    assert :claimed = WelcomeClaim.claim("float-expiry", @now + 1800.9, @now, ScratchRepo)

    assert [[seconds]] =
             rows(
               "SELECT extract(epoch FROM expires_at-statement_timestamp())::float8 FROM phoenix.once_claims WHERE key=$1",
               [key("float-expiry")]
             )

    assert seconds > 1799 and seconds <= 1800
  end

  test "second welcome claim cannot extend a live claim and bad keys never write" do
    assert :claimed = WelcomeClaim.claim("once", @now + 1800, @now, ScratchRepo)
    before = rows("SELECT key, expires_at FROM phoenix.once_claims")
    assert :consumed = WelcomeClaim.claim("once", @now + 3600, @now, ScratchRepo)
    assert rows("SELECT key, expires_at FROM phoenix.once_claims") == before

    for jti <- [nil, 42, <<255>>, String.duplicate("x", 1024)] do
      refute WelcomeClaim.supported?(jti)
      assert {:error, :unsupported_key} = WelcomeClaim.claim(jti, @now + 10, @now, ScratchRepo)
    end

    for exp <- [true, %{}, []] do
      assert {:error, :unsupported_expiry} =
               WelcomeClaim.claim("invalid-expiry", exp, @now, ScratchRepo)
    end

    assert rows("SELECT key, expires_at FROM phoenix.once_claims") == before
  end

  defp key(jti),
    do:
      "trial_welcome:consumed:sha256:" <> Base.encode16(:crypto.hash(:sha256, jti), case: :lower)

  test "two real PG welcome contenders permit exactly one claim" do
    parent = self()

    holder =
      LockRace.hold(fn ->
        assert :claimed = WelcomeClaim.claim("contended", @now + 1800, @now, ScratchRepo)

        send(
          parent,
          {:winning_expiry,
           rows("SELECT expires_at FROM phoenix.once_claims WHERE key=$1", [key("contended")])}
        )
      end)

    assert_receive {:winning_expiry, expiry}

    loser =
      LockRace.attempt(fn -> WelcomeClaim.claim("contended", @now + 3600, @now, ScratchRepo) end)

    assert :blocked = LockRace.settle(loser, "%INSERT INTO phoenix.once_claims%")
    LockRace.commit(holder)
    assert {:ok, :consumed} = Task.await(loser)

    assert rows("SELECT expires_at FROM phoenix.once_claims WHERE key=$1", [key("contended")]) ==
             expiry
  end
end
