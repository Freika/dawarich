defmodule Dawarich.Trips.WebCommandsTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.Jobs.Ownership
  alias Dawarich.Test.RailsUser
  alias Dawarich.Trips.WebCommands

  @key "command:trips.calculate"
  @now ~U[2026-10-03 11:00:00.000000Z]
  @effects "test/fixtures/trips/remaining/effects.json"

  defp requests,
    do:
      rows(
        "SELECT command_type, command_version, payload, metadata, aggregate_id, dedupe_key, scheduled_at FROM job_outbox ORDER BY event_id"
      )

  test "calculation uses locked ownership and exact envelope" do
    user = RailsUser.insert!(%{id: 896_901, email: "a8-command@example.invalid"}, ScratchRepo)
    other = RailsUser.insert!(%{id: 896_902, email: "a8-other@example.invalid"}, ScratchRepo)

    ScratchRepo.insert_all("trips", [
      %{
        id: 896_903,
        user_id: user.id,
        name: "Auwald",
        started_at: DateTime.to_naive(@now),
        ended_at: @now |> DateTime.add(3600) |> DateTime.to_naive(),
        created_at: DateTime.to_naive(@now),
        updated_at: DateTime.to_naive(@now)
      }
    ])

    for owner <- [:missing, :sidekiq] do
      if owner == :sidekiq, do: Ownership.put!(ScratchRepo, @key, :sidekiq)
      assert {:replay, _} = WebCommands.calculate!(ScratchRepo, user, 896_903, "mi", @now)
      assert requests() == []
      assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    end

    Ownership.put!(ScratchRepo, @key, :oban)
    assert {:error, :not_found} = WebCommands.calculate!(ScratchRepo, other, 896_903, "mi", @now)
    assert {:error, :not_found} = WebCommands.calculate!(ScratchRepo, user, 999_999, "mi", @now)
    assert requests() == []

    capture = @effects |> File.read!() |> Jason.decode!() |> Map.fetch!("effects")
    rollback = Enum.find(capture, &(&1["name"] == "update_sql_failure_oban"))
    assert rollback["queue"]["outbox"] == []
    assert rollback["before"]["trips"] == rollback["after"]["trips"]

    assert_raise Postgrex.Error, fn ->
      ScratchRepo.transaction(fn ->
        assert {:ok, :queued} = WebCommands.calculate!(ScratchRepo, user, 896_903, "mi", @now)
        ScratchRepo.query!("UPDATE trips SET user_id = NULL WHERE id = 896903")
      end)
    end

    assert requests() == rollback["queue"]["outbox"]

    assert {:ok, :queued} = WebCommands.calculate!(ScratchRepo, user, 896_903, "mi", @now)

    assert requests() == [
             [
               "trips.calculate",
               1,
               %{"trip_id" => 896_903, "distance_unit" => "mi"},
               %{"producer" => "Trip#enqueue_calculation_jobs"},
               896_903,
               "896903",
               @now
             ]
           ]

    first = requests()

    assert {:ok, :pending} =
             WebCommands.calculate!(ScratchRepo, user, 896_903, "km", DateTime.add(@now, 1))

    assert requests() == first
    rows("UPDATE job_outbox SET state = 'dispatched'")
    assert {:ok, :queued} = WebCommands.calculate!(ScratchRepo, user, 896_903, "km", @now)
    assert length(requests()) == 2

    assert {:ok, :lock_not_available} =
             ScratchRepo.transaction(fn ->
               assert :ok = WebCommands.admission(ScratchRepo)

               contender =
                 Task.async(fn ->
                   error =
                     assert_raise Postgrex.Error, fn ->
                       ScratchRepo.transaction(fn ->
                         ScratchRepo.query!("SET LOCAL lock_timeout = '50ms'")
                         Ownership.put!(ScratchRepo, @key, :sidekiq)
                       end)
                     end

                   error.postgres.code
                 end)

               Task.await(contender)
             end)

    Ownership.put!(ScratchRepo, @key, :sidekiq)
    before = requests()
    assert {:replay, _} = WebCommands.calculate!(ScratchRepo, user, 896_903, "mi", @now)
    assert requests() == before
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
  end
end
