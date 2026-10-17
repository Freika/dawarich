defmodule Dawarich.Stats.Sync1160FailuresTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.Stats.{CalculateMonth, FailureNotice}
  alias Dawarich.Digests.{Failure, Run}
  alias Dawarich.Test.FrameSeeds
  import Dawarich.Test.StatsSeeds

  test "identical unread failure dedupe retains other kinds titles owners and read history" do
    user = FrameSeeds.user!(91603)
    other = FrameSeeds.user!(91604)
    first = FailureNotice.create!(Repo, user.id, :error, "Failure", "same")
    assert FailureNotice.create!(Repo, user.id, :error, "Failure", "same") == first

    for {owner, kind, title, content} <- [
          {other.id, :error, "Failure", "same"},
          {user.id, :warning, "Failure", "same"},
          {user.id, :error, "Other", "same"},
          {user.id, :error, "Failure", "different"}
        ],
        do: FailureNotice.create!(Repo, owner, kind, title, content)

    assert [[5]] =
             rows("SELECT count(*) FROM notifications WHERE user_id=ANY($1)", [
               [user.id, other.id]
             ])

    rows("UPDATE notifications SET read_at=now() WHERE id=$1", [first])
    refute FailureNotice.create!(Repo, user.id, :error, "Failure", "same") == first

    assert [[6]] =
             rows("SELECT count(*) FROM notifications WHERE user_id=ANY($1)", [
               [user.id, other.id]
             ])
  end

  test "persistent stats failure notifies once then succeeds and suppressed digest failure reports once" do
    user = FrameSeeds.user!(91605)
    point!(user.id, %{timestamp: DateTime.to_unix(~U[2025-03-05 12:00:00Z])})
    boom = fn _, _, _, _ -> raise "synthetic persistent failure" end
    opts = [hexagons: boom]

    ExUnit.CaptureLog.capture_log(fn ->
      Enum.each([1, 1, 1], fn _ ->
        assert {:error, _} = CalculateMonth.call(Repo, user.id, 2025, 3, opts)
      end)
    end)

    assert [[1]] = rows("SELECT count(*) FROM notifications WHERE user_id=$1", [user.id])
    assert :ok = CalculateMonth.call(Repo, user.id, 2025, 3, hexagons: fn _, _, _, _ -> %{} end)
    args = %{"user_id" => user.id, "year" => 2025, "month" => 3}
    observer = self()

    stats = fn _, _, _, _, options ->
      send(observer, {:notify, options[:notify]})
      {:error, %RuntimeError{message: "digest stats failed"}}
    end

    for kind <- [:monthly, :yearly] do
      assert {:error, error, _} = apply(Run, kind, [Repo, args, [stats: stats]])
      assert_receive {:notify, false}
      for _ <- 1..3, do: Failure.create!(Repo, kind, user.id, error, [])
    end

    assert [[3]] = rows("SELECT count(*) FROM notifications WHERE user_id=$1", [user.id])
  end

  test "silent full recalculation propagates a stats failure before tracks or digests" do
    user = FrameSeeds.user!(91606)
    point!(user.id, %{timestamp: DateTime.to_unix(~U[2025-03-05 12:00:00Z])})

    stats = fn repo, id, year, month, options ->
      assert options[:notify] == false

      CalculateMonth.call(
        repo,
        id,
        year,
        month,
        Keyword.put(options, :hexagons, fn _, _, _, _ -> raise "silent failure" end)
      )
    end

    ExUnit.CaptureLog.capture_log(fn ->
      assert_raise RuntimeError, "silent failure", fn ->
        Dawarich.Users.Recalculation.run(
          Repo,
          :unused,
          %{"user_id" => user.id, "year" => 2025, "notify" => false},
          stats: stats
        )
      end
    end)

    assert [[0]] = rows("SELECT count(*) FROM notifications WHERE user_id=$1", [user.id])
    assert [[0]] = rows("SELECT count(*) FROM digests WHERE user_id=$1", [user.id])
  end
end
