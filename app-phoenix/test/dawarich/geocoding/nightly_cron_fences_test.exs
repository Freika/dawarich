defmodule Dawarich.Geocoding.NightlyCronFencesTest do
  use Dawarich.JobsCase

  alias Dawarich.Geocoding.{NightlyWorker, NightlyInvalidationWorker}
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Redis

  @oban __MODULE__.Oban
  @env %{"DAWARICH_RAILS" => "off", "PHOTON_API_HOST" => "photon.example.invalid"}
  @slot 1_791_115_200

  setup do
    start_oban(@oban)

    rows(
      "INSERT INTO users(id,email,created_at,updated_at) VALUES(48101,'cron-fence@example.invalid',now(),now())"
    )

    rows(
      "INSERT INTO points(id,user_id,timestamp,created_at,updated_at) VALUES(48301,48101,1791115200,now(),now())"
    )

    :ok
  end

  test "standalone fresh nightly roots and child routes honour pinned rollback ownership" do
    Ownership.put!(ScratchRepo, NightlyWorker.key(), :sidekiq, pinned: true)
    Ownership.put!(ScratchRepo, "command:geocoding.reverse_point", :sidekiq, pinned: true)
    assert NightlyWorker.run(ScratchRepo, @oban, @slot, env: @env) == {:cancel, :not_owner}
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
    assert rows("SELECT count(*) FROM phoenix.processed_commands") == [[0]]
    Ownership.put!(ScratchRepo, NightlyWorker.key(), :oban)
    assert NightlyWorker.run(ScratchRepo, @oban, @slot, env: @env) == :ok

    assert rows(
             "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Geocoding.ReversePointWorker'"
           ) == [[0]]

    assert [["geocoding.reverse_point", %{"point_ids" => [48301]}]] =
             rows(
               "SELECT kind,payload FROM phoenix.rails_commands WHERE kind='geocoding.reverse_point'"
             )
  end

  test "nightly cache eviction is durable after commit and absent after enclosing rollback" do
    Enum.each(Redis.cache_child_specs(), &start_supervised!/1)
    key = "dawarich/user_48101_countries_visited"

    on_exit(fn ->
      {:ok, conn} = Redix.start_link(System.fetch_env!("PHOENIX_TEST_REDIS_URL"))
      Redix.command(conn, ["SELECT", "0"])
      Redix.command(conn, ["DEL", key])
      GenServer.stop(conn)
    end)

    Ownership.put!(ScratchRepo, NightlyWorker.key(), :oban)
    Ownership.put!(ScratchRepo, "command:geocoding.reverse_point", :oban)
    Ownership.put!(ScratchRepo, "command:stats.calculate_month", :oban)
    assert {:ok, "OK"} = Redis.cache_command(["SET", key, "before"])

    assert {:error, :abort} =
             ScratchRepo.transaction(fn ->
               assert :ok = NightlyWorker.run(ScratchRepo, @oban, @slot, env: @env)
               assert {:ok, "before"} = Redis.cache_command(["GET", key])
               ScratchRepo.rollback(:abort)
             end)

    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
    assert rows("SELECT count(*) FROM phoenix.processed_commands") == [[0]]
    assert {:ok, "before"} = Redis.cache_command(["GET", key])
    assert :ok = NightlyWorker.run(ScratchRepo, @oban, @slot, env: @env)
    assert {:ok, "before"} = Redis.cache_command(["GET", key])

    assert [[args]] =
             rows(
               "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Geocoding.NightlyInvalidationWorker'"
             )

    assert :ok =
             NightlyInvalidationWorker.perform(%Oban.Job{args: args, conf: Oban.config(@oban)})

    assert {:ok, nil} = Redis.cache_command(["GET", key])
  end
end
