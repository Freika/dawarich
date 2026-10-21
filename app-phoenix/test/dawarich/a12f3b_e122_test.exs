defmodule Dawarich.A12f3bE122Test do
  use Dawarich.GeocodingCase, async: false
  alias Dawarich.Geocoding.{NightlySweep, NightlyWorker, ReversePointWorker}
  alias Dawarich.Jobs.{Drain, Ownership}
  @oban __MODULE__.Oban
  @slot 1_791_115_200
  @env %{"DAWARICH_RAILS" => "off", "PHOTON_API_HOST" => "e122.example.test"}

  setup do
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    start_oban(@oban)
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))

    rows(
      "INSERT INTO users(id,email,created_at,updated_at) VALUES(61101,'e122@example.test',now(),now())"
    )

    rows(
      "INSERT INTO instance_settings(key,value,created_at,updated_at) VALUES('photon_api_host',$1,now(),now())",
      ["e122.example.test"]
    )

    :ok
  end

  @tag a12f3b_case: "E122a"
  test "E122 native source shapes reach their terminal effects" do
    points(1)
    Ownership.put!(ScratchRepo, NightlyWorker.key(), :oban)
    Ownership.put!(ScratchRepo, "command:geocoding.reverse_point", :oban)
    assert NightlyWorker.run(ScratchRepo, @oban, @slot, env: @env) == :ok

    [[id, args]] =
      rows("SELECT id,args FROM oban.oban_jobs WHERE worker=$1", [inspect(ReversePointWorker)])

    assert args["force"] == false
    assert args["cursor"] == 0
    assert args["event_id"] == NightlySweep.child_id(NightlySweep.root_id(@slot), 61101, [61201])
    Ownership.put!(ScratchRepo, NightlyWorker.key(), :sidekiq, pinned: true)
    Ownership.put!(ScratchRepo, "command:geocoding.reverse_point", :sidekiq, pinned: true)
    config = Dawarich.Geocoding.Config.resolve(ScratchRepo)
    {url, _, _} = Dawarich.Geocoding.Query.build(config, {52.0, 13.0}, [], "synthetic")
    FakeHttp.stub(url, 200, Jason.encode!(%{"features" => []}))
    assert ReversePointWorker.perform(%Oban.Job{args: args, conf: Oban.config(@oban)}) == :ok
    complete(id)
    assert rows("SELECT reverse_geocoded_at IS NOT NULL FROM points WHERE id=61201") == [[true]]

    assert rows("SELECT count(*) FROM phoenix.once_claims WHERE key='geocode:enq:Point:61201'") ==
             [[0]]

    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    accepted = rows("SELECT id,worker,args FROM oban.oban_jobs ORDER BY id")
    assert NightlyWorker.run(ScratchRepo, @oban, @slot, env: @env) == {:cancel, :not_owner}
    assert rows("SELECT id,worker,args FROM oban.oban_jobs ORDER BY id") == accepted
  end

  @tag a12f3b_case: "E122b"
  test "E122 accepted children prevent premature completion" do
    points(1001)
    Ownership.put!(ScratchRepo, NightlyWorker.key(), :oban)
    Ownership.put!(ScratchRepo, "command:geocoding.reverse_point", :oban)
    assert NightlyWorker.run(ScratchRepo, @oban, @slot, env: @env) == :ok
    status = Drain.status(ScratchRepo)
    assert status.counts.incomplete_oban == 11
    assert status.counts.reverse_pending == 0
    assert "incomplete_oban" in status.shutdown_reasons

    [[id, args]] =
      rows("SELECT id,args FROM oban.oban_jobs WHERE worker=$1", [inspect(NightlyWorker)])

    assert args["after_id"] == 62200
    assert args["affected_user_ids"] == [61101]
    Ownership.put!(ScratchRepo, NightlyWorker.key(), :sidekiq, pinned: true)
    assert NightlySweep.run(ScratchRepo, @oban, args, env: @env) == {:cancel, :not_owner}
    complete(id)
    assert NightlySweep.run(ScratchRepo, @oban, args, env: @env) == {:cancel, :not_owner}

    assert rows(
             "SELECT sum(jsonb_array_length(args->'point_ids')) FROM oban.oban_jobs WHERE worker=$1",
             [inspect(ReversePointWorker)]
           ) == [[1000]]

    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    assert Drain.status(ScratchRepo).counts.incomplete_oban == 11

    assert [[cleanup_id, payload]] =
             rows(
               "SELECT id,args FROM oban.oban_jobs WHERE worker='Dawarich.Geocoding.NightlyInvalidationWorker'"
             )

    assert :ok =
             Dawarich.Geocoding.NightlyInvalidationWorker.perform(%Oban.Job{
               args: payload,
               conf: Oban.config(@oban)
             })

    complete(cleanup_id)
    assert Drain.status(ScratchRepo).counts.incomplete_oban == 10
  end

  defp points(count),
    do:
      rows(
        "INSERT INTO points(id,user_id,timestamp,lonlat,created_at,updated_at) SELECT 61200+n,61101,1791115200+n,ST_GeogFromText('POINT(13 52)'),now(),now() FROM generate_series(1,$1::integer) n",
        [count]
      )

  defp complete(id),
    do: rows("UPDATE oban.oban_jobs SET state='completed',completed_at=now() WHERE id=$1", [id])
end
