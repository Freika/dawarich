defmodule Dawarich.Jobs.RecalculationEntriesTest do
  use Dawarich.JobsCase

  alias Dawarich.Jobs.{Dispatch, Registry}
  alias Dawarich.Users.RecalculateWorker

  test "disabled user rebuild entry dispatches complete payloads to the real Oban worker" do
    oban = :recalculation_entries
    start_oban(oban)
    entry = Enum.find(Registry.entries(), &(&1.key == "command:users.recalculate_data"))
    assert %{kind: :command, claimable: false, worker: RecalculateWorker} = entry
    refute entry in Registry.claimable()
    assert Registry.command("users.recalculate_data") == {:ok, RecalculateWorker}

    payload = %{
      "user_id" => 170_101,
      "year" => 2025,
      "notify" => false,
      "job_queue" => "low_priority",
      "source_job_id" => Ecto.UUID.generate(),
      "ambient_zone" => "Asia/Tokyo"
    }

    assert RecalculateWorker.args_from_command(1, payload) == {:ok, payload}
    event = outbox!(command_type: "users.recalculate_data", payload: payload)
    assert Dispatch.run(repo: ScratchRepo, oban: oban) == %{dispatched: 1}

    assert [[args, "Dawarich.Users.RecalculateWorker", "projections"]] =
             rows("SELECT args,worker,queue FROM oban.oban_jobs")

    assert args == Map.put(payload, "event_id", event)
    assert rows("SELECT count(*) FROM phoenix.job_owners") == [[0]]

    assert rows("SELECT state FROM public.job_outbox WHERE event_id=$1", [Ecto.UUID.dump!(event)]) ==
             [["dispatched"]]
  end
end
