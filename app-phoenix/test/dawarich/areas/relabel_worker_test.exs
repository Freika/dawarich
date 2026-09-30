defmodule Dawarich.Areas.RelabelWorkerTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db
  use Oban.Testing, repo: Dawarich.ScratchRepo

  alias Dawarich.Areas.RelabelWorker
  alias Dawarich.Jobs.Dispatch

  @oban Dawarich.AreasRelabelWorkerTestOban

  defp dispatch,
    do:
      Dispatch.run(
        repo: ScratchRepo,
        oban: @oban,
        commands: fn "areas.relabel_visits" -> {:ok, RelabelWorker} end
      )

  defp relabel!(area_id),
    do: outbox!(command_type: "areas.relabel_visits", payload: %{"area_id" => area_id})

  test "decodes version 1 payloads exactly" do
    assert RelabelWorker.args_from_command(1, %{"area_id" => 3}) == {:ok, %{"area_id" => 3}}
    assert RelabelWorker.args_from_command(1, %{"area_id" => "3"}) == {:error, "invalid_payload"}
    assert RelabelWorker.args_from_command(2, %{}) == {:error, "unsupported_version"}
  end

  test "an outbox row dispatches to the relabel worker on the projections queue with 2 attempts" do
    start_oban(@oban)
    id = relabel!(3)

    assert dispatch() == %{dispatched: 1}

    assert rows("SELECT worker, queue, max_attempts, args FROM oban.oban_jobs") == [
             [
               "Dawarich.Areas.RelabelWorker",
               "projections",
               2,
               %{"area_id" => 3, "event_id" => id}
             ]
           ]
  end

  test "a waiting relabel absorbs later ones for its area however old it is, a running one does not" do
    start_oban(@oban)
    relabel!(3)
    relabel!(4)
    assert dispatch() == %{dispatched: 2}
    rows("UPDATE oban.oban_jobs SET inserted_at = now() - interval '30 days'")

    relabel!(3)
    assert dispatch() == %{dispatched: 1}
    assert rows("SELECT args->>'area_id' FROM oban.oban_jobs ORDER BY id") == [["3"], ["4"]]

    for state <- ~w(scheduled retryable) do
      rows("UPDATE oban.oban_jobs SET state = $1 WHERE args->>'area_id' = '3'", [state])
      relabel!(3)
      assert dispatch() == %{dispatched: 1}
      assert rows("SELECT count(*) FROM oban.oban_jobs") == [[2]]
    end

    rows("UPDATE oban.oban_jobs SET state = 'executing' WHERE args->>'area_id' = '3'")
    relabel!(3)
    assert dispatch() == %{dispatched: 1}

    assert rows("SELECT args->>'area_id', state FROM oban.oban_jobs ORDER BY id") == [
             ["3", "executing"],
             ["4", "available"],
             ["3", "available"]
           ]
  end

  test "a job for a missing area completes" do
    assert perform_job(RelabelWorker, %{"event_id" => Ecto.UUID.generate(), "area_id" => 0}) ==
             :ok
  end
end
