defmodule Dawarich.ReleaseOperations.VisitsFleetRedetectTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.{ReleaseOperations, Wave6Fixtures}
  alias Dawarich.ReleaseOperations.VisitsFleetRedetect

  @oban Dawarich.ReleaseOperations.VisitsFleetRedetectTest.Oban
  @start %{"after_id" => 0, "started_at" => nil, "offset" => 0}

  setup do
    Wave6Fixtures.reset!()
    start_oban(@oban)
    :ok
  end

  test "active users with points get one row each, 30 s apart from one start" do
    first = Wave6Fixtures.user!(%{"points_count" => 4})
    second = Wave6Fixtures.user!(%{"points_count" => 1})
    Wave6Fixtures.user!(%{"points_count" => 4, "status" => 0})
    Wave6Fixtures.user!(%{"points_count" => 0})
    Wave6Fixtures.user!(%{"points_count" => 4, "deleted_at" => NaiveDateTime.utc_now()})
    before = System.os_time(:second)

    {id, :ok} = run(%{"version" => 1, "event_id" => Ecto.UUID.generate(), "cursor" => @start})

    assert [
             %{"user_id" => ^first, "run_at" => started},
             %{"user_id" => ^second, "run_at" => later}
           ] = commands()

    assert started >= before and started <= System.os_time(:second)
    assert later == started + 30
    assert status(id) == "completed"
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
  end

  test "a full page carries start and offset to the next page" do
    rows("""
    INSERT INTO users (email, status, points_count, settings, created_at, updated_at)
    SELECT 'fleet-' || g || '@example.test', 1, 1, '{}', now(), now() FROM generate_series(1, 501) g
    """)

    [[last_id]] = rows("SELECT max(id) FROM users")

    {id, :ok} = run(%{"version" => 1, "event_id" => Ecto.UUID.generate(), "cursor" => @start})

    first_page = commands()
    assert length(first_page) == 500
    started = hd(first_page)["run_at"]
    assert List.last(first_page)["run_at"] == started + 499 * 30

    assert [[successor]] = rows("SELECT args FROM oban.oban_jobs")

    assert %{
             "operation_id" => ^id,
             "cursor" => %{"started_at" => ^started, "offset" => 15_000, "after_id" => after_id}
           } = successor

    assert after_id == List.last(first_page)["user_id"]

    assert run(successor) == {id, :ok}
    assert Enum.drop(commands(), 500) == [%{"user_id" => last_id, "run_at" => started + 15_000}]
    assert status(id) == "completed"
  end

  test "decodes version 1 payloads exactly" do
    assert VisitsFleetRedetect.args_from_command(1, %{}) ==
             {:ok, %{"version" => 1, "cursor" => @start}}

    assert VisitsFleetRedetect.args_from_command(1, %{"after_id" => 0}) ==
             {:error, "invalid_payload"}

    assert VisitsFleetRedetect.args_from_command(2, %{}) == {:error, "unsupported_version"}
  end

  defp run(args) do
    job = %Oban.Job{args: args, attempt: 1, max_attempts: 10}

    {args["event_id"] || args["operation_id"],
     ReleaseOperations.run(ScratchRepo, @oban, VisitsFleetRedetect, job)}
  end

  defp commands,
    do:
      "SELECT payload FROM phoenix.rails_commands WHERE kind = 'release_user_redetect' ORDER BY id"
      |> rows()
      |> List.flatten()

  defp status(id) do
    [[status]] =
      rows("SELECT status FROM phoenix.release_operations WHERE id = $1", [Ecto.UUID.dump!(id)])

    status
  end
end
