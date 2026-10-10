defmodule Dawarich.Stats.PageRefreshTest do
  use Dawarich.DataCase, async: true
  import Dawarich.Test.StatsSeeds
  alias Dawarich.Accounts.Scope
  alias Dawarich.Stats.{PageRefresh, PageRefreshWorker}
  alias Dawarich.Test.FrameSeeds

  setup do
    scope = Scope.for_user(FrameSeeds.user!(8711, %{"timezone" => "UTC"}), "de")

    stat!(scope.user.id, %{
      year: 2025,
      month: 3,
      distance: 1000,
      daily_distance: [[1, 1000]],
      updated_at: ~N[2025-04-01 00:00:00]
    })

    %{scope: scope, params: %{"year" => "2025", "month" => "3"}}
  end

  test "cold and stale Insights mounts publish one refresh and never calculate inline", %{
    scope: scope,
    params: params
  } do
    assert {:ok, %{state: :pending}} =
             Dawarich.Insights.Pages.details(scope, params, self_hosted: true)

    assert rows("SELECT id FROM digests WHERE user_id=$1", [scope.user.id]) == []
    assert {:ok, first} = PageRefresh.request(scope, :insights, params, self_hosted: true)
    assert {:ok, second} = PageRefresh.request(scope, :insights, params, self_hosted: true)
    assert first.receipt == second.receipt
    assert first.state == :pending

    assert rows("SELECT count(*) FROM oban.oban_jobs WHERE worker=$1", [
             "Dawarich.Stats.PageRefreshWorker"
           ]) == [[1]]

    assert rows("SELECT id FROM digests WHERE user_id=$1", [scope.user.id]) == []

    assert {:ok, %{state: :ready}} =
             PageRefresh.request(scope, :insights, %{"year" => "all"}, self_hosted: true)

    assert {:ok, scope} = Dawarich.Accounts.DataAccess.admit(scope)
    Repo.query!("UPDATE users SET plan=0 WHERE id=$1", [scope.user.id], log: false)

    assert {:ok, %{state: :restricted}} =
             PageRefresh.request(scope, :insights, params, self_hosted: false)

    assert rows("SELECT count(*) FROM oban.oban_jobs WHERE worker=$1", [
             "Dawarich.Stats.PageRefreshWorker"
           ]) == [[1]]
  end

  test "a newer stats revision can refresh after a published period", %{
    scope: scope,
    params: params
  } do
    assert {:ok, first} = PageRefresh.request(scope, :insights, params, self_hosted: true)
    assert :ok = PageRefreshWorker.run(first.args, repo: Repo)

    assert {:ok, %{state: :ready}} =
             PageRefresh.request(scope, :insights, params, self_hosted: true)

    Repo.query!(
      "UPDATE stats SET distance=2000,daily_distance='[[1,2000]]',updated_at=updated_at+interval '1 second' WHERE user_id=$1",
      [scope.user.id],
      log: false
    )

    assert {:ok, second} = PageRefresh.request(scope, :insights, params, self_hosted: true)
    refute second.receipt == first.receipt
    assert second.state == :pending
    assert :ok = PageRefreshWorker.run(second.args, repo: Repo)

    assert rows("SELECT distance FROM digests WHERE user_id=$1 AND period_type=1", [scope.user.id]) ==
             [[2000]]

    assert {:ok, %{state: :ready}} =
             PageRefresh.request(scope, :insights, params, self_hosted: true)
  end

  test "failed automatic refresh retries the existing durable job and counts expire into a new revision",
       %{scope: scope, params: params} do
    {:ok, refresh} = PageRefresh.request(scope, :insights, params, self_hosted: true)

    assert {:error, :calculation_failed} =
             PageRefreshWorker.run(refresh.args,
               repo: Repo,
               before_ready: fn -> raise "synthetic" end
             )

    Repo.query!(
      "UPDATE oban.oban_jobs SET state='discarded' WHERE args->>'receipt'=$1",
      [refresh.receipt],
      log: false
    )

    assert {:ok, %{state: :pending}} =
             apply(PageRefresh, :retry, [scope, :insights, params, [self_hosted: true]])

    assert rows("SELECT state FROM oban.oban_jobs WHERE args->>'receipt'=$1", [refresh.receipt]) ==
             [["available"]]

    assert rows("SELECT count(*) FROM oban.oban_jobs WHERE args->>'receipt'=$1", [refresh.receipt]) ==
             [[1]]

    {:ok, first} =
      PageRefresh.request(scope, :counts, %{}, self_hosted: true, now: ~U[2026-10-01 12:00:00Z])

    {:ok, later} =
      PageRefresh.request(scope, :counts, %{}, self_hosted: true, now: ~U[2026-10-03 12:00:00Z])

    refute first.receipt == later.receipt
    assert :ok = PageRefreshWorker.run(later.args, repo: Repo, now: ~U[2026-10-03 12:00:00Z])

    assert rows("SELECT geocoded,without_data FROM phoenix.stats_point_counts WHERE user_id=$1", [
             scope.user.id
           ]) == [[0, 0]]
  end

  test "concurrent static and connected subscribers converge on one durable intent", %{
    scope: scope,
    params: params
  } do
    parent = self()

    tasks =
      for _ <- 1..2 do
        task =
          Task.async(fn ->
            receive do
              :go -> :ok
            end

            PageRefresh.request(scope, :insights, params,
              self_hosted: true,
              before_claim: fn ->
                send(parent, {:claim_ready, self()})

                receive do
                  :claim -> :ok
                end
              end
            )
          end)

        Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), task.pid)
        task
      end

    try do
      for task <- tasks, do: send(task.pid, :go)
      assert_receive {:claim_ready, first}, 1000
      assert_receive {:claim_ready, second}, 1000
      refute first == second
      for task <- tasks, do: send(task.pid, :claim)
      results = Enum.map(tasks, &Task.await/1)
      assert [{:ok, one}, {:ok, two}] = results
      assert one.receipt == two.receipt

      assert rows("SELECT count(*) FROM oban.oban_jobs WHERE args->>'receipt'=$1", [one.receipt]) ==
               [[1]]
    after
      for task <- tasks do
        send(task.pid, :go)
        send(task.pid, :claim)
        if Process.alive?(task.pid), do: Task.await(task)
      end
    end
  end
end
