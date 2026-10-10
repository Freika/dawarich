defmodule Dawarich.PointExportsFenceTest do
  use Dawarich.JobsCase
  alias Dawarich.PointExports
  alias Dawarich.Jobs.Ownership

  defmodule PausedRepo do
    def transaction(fun), do: Dawarich.ScratchRepo.transaction(fun)

    def query!(sql, params, opts \\ []) do
      if String.contains?(sql, "INSERT INTO exports (") do
        send(Process.get(:direct_export_gate_parent), {:before_insert, self()})
        receive do: (:proceed -> :ok)
      end

      Dawarich.ScratchRepo.query!(sql, params, opts)
    end
  end

  test "owner transfer waits for the real creation transaction, then the next create routes to Rails" do
    [[user_id]] =
      rows(
        "INSERT INTO users (email, created_at, updated_at) VALUES ('export-fence@example.test', now(), now()) RETURNING id"
      )

    user = %{id: user_id, settings: %{"timezone" => "UTC"}}
    key = "command:exports.points"
    Ownership.put!(ScratchRepo, key, :oban)

    {:ok, export} =
      PointExports.parse(%{
        "start_at" => "2024-03-01 00:00:00 UTC",
        "end_at" => "2024-03-31 00:00:00 UTC",
        "file_format" => "json"
      })

    parent = self()

    holder =
      Task.async(fn ->
        Process.put(:direct_export_gate_parent, parent)
        PointExports.create(export, user, "en", PausedRepo)
      end)

    try do
      assert_receive {:before_insert, _pid}, 5_000

      error =
        assert_raise Postgrex.Error, fn ->
          ScratchRepo.transaction(fn ->
            ScratchRepo.query!("SET LOCAL lock_timeout = '50ms'")

            ScratchRepo.query!("UPDATE phoenix.job_owners SET owner = 'sidekiq' WHERE key = $1", [
              key
            ])
          end)
        end

      assert error.postgres.code == :lock_not_available
    after
      send(holder.pid, :proceed)
    end

    assert {:ok, id} = Task.await(holder, 5_000)
    assert [[id]] == rows("SELECT aggregate_id FROM job_outbox")
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    Ownership.put!(ScratchRepo, key, :sidekiq)
    assert {:ok, next} = PointExports.create(export, user, "en", ScratchRepo)
    assert [[%{"export_id" => ^next}]] = rows("SELECT payload FROM phoenix.rails_commands")
    assert rows("SELECT count(*) FROM job_outbox") == [[1]]
  end
end
