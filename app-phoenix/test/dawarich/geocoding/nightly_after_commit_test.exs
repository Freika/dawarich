defmodule Dawarich.Geocoding.NightlyAfterCommitTest do
  use Dawarich.JobsCase

  alias Dawarich.AfterCommit.Visibility
  alias Dawarich.Geocoding.{NightlyInvalidationWorker, NightlySweep, NightlyWorker}
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Redis

  @oban __MODULE__.Oban
  @user 48111
  @env %{"DAWARICH_RAILS" => "off", "PHOTON_API_HOST" => "nightly.example.invalid"}
  @args %{"slot" => 1_791_115_200, "after_id" => 0, "affected_user_ids" => [@user]}
  @key "dawarich/user_#{@user}_countries_visited"

  setup do
    start_oban(@oban)
    Enum.each(Redis.cache_child_specs(), &start_supervised!/1)

    rows(
      "INSERT INTO users(id,email,created_at,updated_at) VALUES($1,'nightly-after-commit@example.invalid',now(),now())",
      [@user]
    )

    Ownership.put!(ScratchRepo, NightlyWorker.key(), :oban)
    Ownership.put!(ScratchRepo, "command:stats.calculate_month", :oban)
    assert {:ok, "OK"} = Redis.cache_command(["SET", @key, "before"])

    on_exit(fn ->
      {:ok, conn} = Redix.start_link(System.fetch_env!("PHOENIX_TEST_REDIS_URL"))
      Redix.command(conn, ["SELECT", "0"])
      Redix.command(conn, ["DEL", @key])
      GenServer.stop(conn)
    end)

    :ok
  end

  test "R1 merged nightly producer commits visibility with its durable cleanup" do
    assert Visibility.generation(ScratchRepo, @user) == ""

    assert {:error, :abort} =
             ScratchRepo.transaction(fn ->
               assert :ok = NightlySweep.run(ScratchRepo, @oban, @args, env: @env)
               assert Visibility.generation(ScratchRepo, @user) != ""
               assert {:ok, "before"} = Redis.cache_command(["GET", @key])
               ScratchRepo.rollback(:abort)
             end)

    assert Visibility.generation(ScratchRepo, @user) == ""
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
    assert :ok = NightlySweep.run(ScratchRepo, @oban, @args, env: @env)
    assert Visibility.generation(ScratchRepo, @user) != ""
    assert {:ok, "before"} = Redis.cache_command(["GET", @key])
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[1]]
  end

  test "R1 merged nightly cleanup consumes its accepted job without a second intent" do
    assert :ok = NightlySweep.run(ScratchRepo, @oban, @args, env: @env)

    assert [[payload]] =
             rows(
               "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Geocoding.NightlyInvalidationWorker'"
             )

    job = %Oban.Job{args: payload, conf: Oban.config(@oban)}
    assert :ok = NightlyInvalidationWorker.perform(job)
    assert {:ok, nil} = Redis.cache_command(["GET", @key])
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[1]]
    assert :ok = NightlyInvalidationWorker.perform(job)
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[1]]
  end
end
