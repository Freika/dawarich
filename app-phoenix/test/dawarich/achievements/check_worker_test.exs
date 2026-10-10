defmodule Dawarich.Achievements.CheckWorkerTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db
  use Oban.Testing, repo: Dawarich.ScratchRepo

  alias Dawarich.Achievements.CheckWorker
  alias Dawarich.Jobs.Dispatch

  @oban Dawarich.AchievementsCheckTestOban

  test "decodes version 1 payloads exactly" do
    valid = %{"user_id" => 7, "notify" => true, "oldest_timestamp" => nil}

    assert CheckWorker.args_from_command(1, valid) == {:ok, valid}

    assert CheckWorker.args_from_command(1, %{valid | "oldest_timestamp" => 1_780_300_800}) ==
             {:ok, %{valid | "oldest_timestamp" => 1_780_300_800}}

    assert CheckWorker.args_from_command(1, Map.put(valid, "force", true)) ==
             {:error, "invalid_payload"}

    assert CheckWorker.args_from_command(1, %{valid | "notify" => "true"}) ==
             {:error, "invalid_payload"}

    assert CheckWorker.args_from_command(1, %{valid | "user_id" => "7"}) ==
             {:error, "invalid_payload"}

    assert CheckWorker.args_from_command(2, valid) == {:error, "unsupported_version"}
  end

  test "an outbox row dispatches to the check worker" do
    start_oban(@oban)

    id =
      outbox!(
        command_type: "achievements.check",
        payload: %{"user_id" => 7, "notify" => false, "oldest_timestamp" => 1_780_300_800},
        aggregate_id: 7
      )

    commands = fn "achievements.check" -> {:ok, CheckWorker} end

    assert Dispatch.run(
             now: Dawarich.JobsCase.db_now(ScratchRepo),
             repo: ScratchRepo,
             oban: @oban,
             commands: commands
           ) == %{dispatched: 1}

    assert rows("SELECT worker, queue, max_attempts, args FROM oban.oban_jobs") == [
             [
               "Dawarich.Achievements.CheckWorker",
               "projections",
               25,
               %{
                 "user_id" => 7,
                 "notify" => false,
                 "oldest_timestamp" => 1_780_300_800,
                 "event_id" => id
               }
             ]
           ]
  end

  test "a job for a missing user completes" do
    assert perform_job(CheckWorker, %{
             "event_id" => Ecto.UUID.generate(),
             "user_id" => 0,
             "notify" => true,
             "oldest_timestamp" => nil
           }) == :ok
  end
end
