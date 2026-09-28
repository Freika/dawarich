defmodule Dawarich.Areas.RelabelWorkerTest do
  use Dawarich.JobsCase
  use Oban.Testing, repo: Dawarich.ScratchRepo

  alias Dawarich.Areas.RelabelWorker

  test "decodes version 1 payloads exactly" do
    assert RelabelWorker.args_from_command(1, %{"area_id" => 3}) == {:ok, %{"area_id" => 3}}
    assert RelabelWorker.args_from_command(1, %{"area_id" => "3"}) == {:error, "invalid_payload"}
    assert RelabelWorker.args_from_command(2, %{}) == {:error, "unsupported_version"}
  end

  test "an outbox row dispatches to the relabel worker" do
    id = outbox!(command_type: "areas.relabel_visits", payload: %{"area_id" => 3})
    oban = Dawarich.AreasRelabelWorkerTestOban
    start_oban(oban)

    assert Dawarich.Jobs.Dispatch.run(
             repo: ScratchRepo,
             oban: oban,
             commands: fn "areas.relabel_visits" -> {:ok, RelabelWorker} end
           ) == %{dispatched: 1}

    assert [[%{"area_id" => 3, "event_id" => ^id}]] = rows("SELECT args FROM oban.oban_jobs")
  end
end
