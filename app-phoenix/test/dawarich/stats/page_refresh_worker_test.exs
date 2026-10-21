defmodule Dawarich.Stats.PageRefreshWorkerTest do
  use Dawarich.DataCase, async: true
  import Dawarich.Test.StatsSeeds
  alias Dawarich.Accounts.Scope
  alias Dawarich.Stats.{PageRefresh, PageRefreshWorker}
  alias Dawarich.Test.FrameSeeds

  setup do
    scope = Scope.for_user(FrameSeeds.user!(8721, %{"timezone" => "UTC"}), "en")
    stat!(scope.user.id, %{year: 2025, month: 3, distance: 1000, daily_distance: [[1, 1000]]})

    {:ok, refresh} =
      PageRefresh.request(scope, :insights, %{"year" => "2025", "month" => "3"},
        self_hosted: true
      )

    %{scope: scope, refresh: refresh}
  end

  test "automatic refresh sends no manual digest mail", %{scope: scope, refresh: refresh} do
    assert :ok = PageRefreshWorker.run(refresh.args, repo: Repo)
    assert :ok = PageRefreshWorker.run(refresh.args, repo: Repo)

    assert rows(
             "SELECT period_type,distance FROM digests WHERE user_id=$1 ORDER BY period_type",
             [scope.user.id]
           ) == [[0, 1000], [1, 1000]]

    assert rows(
             "SELECT command_type FROM job_outbox WHERE command_type LIKE 'mail.%' OR command_type LIKE 'digests.%'"
           ) == []

    assert rows(
             "SELECT id FROM oban.oban_jobs WHERE worker LIKE '%Mail%' OR worker LIKE '%YearlyWorker%'"
           ) == []

    assert rows(
             "SELECT kind FROM phoenix.rails_commands WHERE kind IN ('digests.email_month','digests.email_year')"
           ) == []

    assert rows("SELECT count(*) FROM phoenix.processed_commands WHERE event_id=$1", [
             Ecto.UUID.dump!(refresh.receipt)
           ]) == [[1]]

    assert {:ok, %{state: :ready, totals: %{distance: 1}}} =
             Dawarich.Insights.Pages.details(scope, %{"year" => "2025", "month" => "3"},
               self_hosted: true
             )
  end

  test "worker failure retries without a partial ready projection", %{
    scope: scope,
    refresh: refresh
  } do
    assert {:error, :calculation_failed} =
             PageRefreshWorker.run(refresh.args,
               repo: Repo,
               before_ready: fn -> raise "synthetic refusal" end
             )

    assert rows("SELECT id FROM digests WHERE user_id=$1", [scope.user.id]) == []

    assert rows("SELECT event_id FROM phoenix.processed_commands WHERE event_id=$1", [
             Ecto.UUID.dump!(refresh.receipt)
           ]) == []

    assert {:ok, failed} =
             PageRefresh.request(scope, :insights, %{"year" => "2025", "month" => "3"},
               self_hosted: true
             )

    assert failed.state == :failed
    assert failed.receipt == refresh.receipt
    assert :ok = PageRefreshWorker.run(refresh.args, repo: Repo)

    assert {:ok, %{state: :ready}} =
             PageRefresh.request(scope, :insights, %{"year" => "2025", "month" => "3"},
               self_hosted: true
             )
  end

  test "deleting the actor before job execution prevents private output", %{
    scope: scope,
    refresh: refresh
  } do
    Repo.query!("UPDATE users SET deleted_at=now() WHERE id=$1", [scope.user.id], log: false)

    assert {:cancel, :unauthorized} =
             PageRefreshWorker.run(refresh.args,
               repo: Repo,
               calculate: fn _, _, _ -> flunk("deleted actor reached calculation") end
             )

    assert rows("SELECT id FROM digests WHERE user_id=$1", [scope.user.id]) == []

    assert rows("SELECT event_id FROM phoenix.processed_commands WHERE event_id=$1", [
             Ecto.UUID.dump!(refresh.receipt)
           ]) == []
  end

  test "a changed input during calculation cannot publish an old ready result", %{
    scope: scope,
    refresh: refresh
  } do
    parent = self()

    task =
      Task.async(fn ->
        receive do
          :go -> :ok
        end

        PageRefreshWorker.run(refresh.args,
          repo: Repo,
          before_persist: fn ->
            send(parent, {:computed, self()})

            receive do
              :persist -> :ok
            end
          end
        )
      end)

    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), task.pid)
    send(task.pid, :go)
    assert_receive {:computed, pid}, 1000
    assert pid == task.pid

    Repo.query!(
      "UPDATE stats SET distance=2000,updated_at=updated_at+interval '1 second' WHERE user_id=$1",
      [scope.user.id],
      log: false
    )

    send(task.pid, :persist)
    assert Task.await(task) == {:cancel, :stale}
    assert rows("SELECT id FROM digests WHERE user_id=$1", [scope.user.id]) == []

    assert rows("SELECT event_id FROM phoenix.processed_commands WHERE event_id=$1", [
             Ecto.UUID.dump!(refresh.receipt)
           ]) == []
  end
end
