defmodule Dawarich.Geocoding.NightlyWorkerTest do
  use Dawarich.JobsCase

  alias Dawarich.Geocoding.{NightlySweep, NightlyWorker, ReversePointWorker}
  alias Dawarich.Jobs.Ownership
  alias Dawarich.State

  @oban __MODULE__.Oban
  @slot 1_791_115_200
  @env %{"PHOTON_API_HOST" => "photon.example.invalid"}
  @fixture Path.expand("../../fixtures/a12d3/schedules.json", __DIR__)

  setup do
    start_oban(@oban)
    :ok
  end

  test "nightly geocoding publishes every source pending point once without force and with bounded leaf IDs" do
    cases =
      Jason.decode!(File.read!(@fixture))["classes"]["Points::NightlyReverseGeocodingJob"][
        "cases"
      ]

    for profile <- ~w(selection dedup batches disabled), owner <- [:oban, :sidekiq] do
      reset!(ScratchRepo)
      f = Enum.find(cases, &(&1["id"] == profile))
      load_points(f, profile)
      Ownership.put!(ScratchRepo, NightlyWorker.key(), :oban)
      Ownership.put!(ScratchRepo, "command:geocoding.reverse_point", owner)
      env = if profile == "disabled", do: %{}, else: @env

      expected =
        f["jobs"]
        |> Enum.map(fn job ->
          [_, id, _] = job["arguments"]
          id
        end)
        |> Enum.sort()

      if profile == "dedup",
        do: Enum.each([48301, 48303], &State.claim(ScratchRepo, "geocode:enq:Point:#{&1}", 3600))

      assert NightlyWorker.run(ScratchRepo, @oban, @slot, env: env) == :ok
      continue(env)

      native =
        rows(
          "SELECT args FROM oban.oban_jobs WHERE worker = 'Dawarich.Geocoding.ReversePointWorker' ORDER BY id"
        )

      reverse =
        rows(
          "SELECT kind, payload FROM phoenix.rails_commands WHERE kind = 'geocoding.reverse_point' ORDER BY id"
        )

      payloads =
        if owner == :oban, do: Enum.map(native, &hd/1), else: Enum.map(reverse, &List.last/1)

      assert Enum.flat_map(payloads, & &1["point_ids"]) |> Enum.sort() == expected
      assert length(expected) == length(Enum.uniq(Enum.flat_map(payloads, & &1["point_ids"])))
      if owner == :oban, do: assert(reverse == []), else: assert(native == [])

      for payload <- payloads do
        assert payload["force"] == false
        assert length(payload["point_ids"]) <= 100
        data = Map.take(payload, ~w(user_id point_ids force))
        assert {:ok, _} = ReversePointWorker.args_from_command(1, data)

        assert rows(
                 "SELECT count(*) FROM points WHERE id = ANY($1::bigint[]) AND user_id <> $2",
                 [payload["point_ids"], payload["user_id"]]
               ) == [[0]]
      end

      assert rows("SELECT count(*) FROM phoenix.once_claims WHERE key LIKE 'geocode:enq:Point:%'") ==
               [[length(expected) + if(profile == "dedup", do: 2, else: 0)]]

      assert NightlyWorker.run(ScratchRepo, @oban, @slot, env: env) == :ok
      continue(env)

      assert rows(
               "SELECT args FROM oban.oban_jobs WHERE worker = 'Dawarich.Geocoding.ReversePointWorker' ORDER BY id"
             ) == native

      assert rows(
               "SELECT kind, payload FROM phoenix.rails_commands WHERE kind = 'geocoding.reverse_point' ORDER BY id"
             ) == reverse
    end

    reset!(ScratchRepo)
    load_points(Enum.find(cases, &(&1["id"] == "selection")), "selection")
    Ownership.put!(ScratchRepo, NightlyWorker.key(), :oban)
    Ownership.put!(ScratchRepo, "command:geocoding.reverse_point", :oban)

    assert_raise Postgrex.Error, fn ->
      NightlyWorker.run(ScratchRepo, @oban, @slot,
        env: @env,
        hook: fn _ -> ScratchRepo.query!("SELECT 1 / 0", [], log: false) end
      )
    end

    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
    assert rows("SELECT count(*) FROM phoenix.processed_commands") == [[0]]
  end

  defp load_points(f, profile) do
    for id <- [48_101, 48_102] do
      rows(
        "INSERT INTO users (id,email,status,plan,created_at,updated_at,deleted_at) VALUES ($1,$2,1,1,now(),now(),$3)",
        [
          id,
          "nightly-#{id}@example.invalid",
          if(profile == "selection" and id == 48_102, do: ~N[2026-10-04 12:00:00], else: nil)
        ]
      )
    end

    batches =
      if f["batches"] == [],
        do: [%{"user_id" => 48_101, "point_ids" => [48_301]}],
        else: f["batches"]

    for batch <- batches, id <- batch["point_ids"] do
      rows(
        "INSERT INTO points (id,user_id,timestamp,lonlat,anomaly,created_at,updated_at) " <>
          "VALUES ($1,$2,1791115200 + $1::bigint,ST_GeogFromText('POINT(13 52)'),true,now(),now())",
        [id, batch["user_id"]]
      )
    end

    rows(
      "INSERT INTO points (id,user_id,timestamp,reverse_geocoded_at,created_at,updated_at) " <>
        "VALUES (48302,48101,1791115200,now(),now(),now())"
    )
  end

  test "native nightly sweep stops new batches after pinned Sidekiq release and preserves accepted leaves and pending invalidation" do
    f =
      Jason.decode!(File.read!(@fixture))["classes"]["Points::NightlyReverseGeocodingJob"][
        "cases"
      ]
      |> Enum.find(&(&1["id"] == "batches"))

    load_points(f, "batches")
    Ownership.put!(ScratchRepo, NightlyWorker.key(), :oban)
    Ownership.put!(ScratchRepo, "command:geocoding.reverse_point", :oban)
    assert NightlyWorker.run(ScratchRepo, @oban, @slot, env: @env) == :ok

    accepted =
      rows(
        "SELECT args FROM oban.oban_jobs WHERE worker = 'Dawarich.Geocoding.ReversePointWorker' ORDER BY id"
      )

    assert length(accepted) == 11
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]

    assert [[next]] =
             rows(
               "SELECT args FROM oban.oban_jobs WHERE worker = 'Dawarich.Geocoding.NightlyWorker'"
             )

    Ownership.put!(ScratchRepo, NightlyWorker.key(), :sidekiq, pinned: true)
    result = NightlySweep.run(ScratchRepo, @oban, next, env: @env)

    assert rows(
             "SELECT args FROM oban.oban_jobs WHERE worker = 'Dawarich.Geocoding.ReversePointWorker' ORDER BY id"
           ) == accepted

    assert result == {:cancel, :not_owner}
    intents = rows("SELECT kind, payload FROM phoenix.rails_commands ORDER BY id")

    assert intents ==
             Enum.map(
               [48_101, 48_102],
               &["stats.caches_invalidated", %{"user_id" => &1, "year" => nil, "scope" => "all"}]
             )

    assert NightlySweep.run(ScratchRepo, @oban, next, env: @env) == {:cancel, :not_owner}
    assert rows("SELECT kind, payload FROM phoenix.rails_commands ORDER BY id") == intents
    Ownership.put!(ScratchRepo, "command:geocoding.reverse_point", :sidekiq, pinned: true)
    [leaf] = Enum.find(accepted, fn [args] -> args["point_ids"] == [48_303] end)

    rows(
      "INSERT INTO instance_settings (key, value, created_at, updated_at) VALUES ('photon_api_host',$1,now(),now())",
      ["photon.example.invalid"]
    )

    start_supervised!(Dawarich.Geocoding.FakeHttp)
    start_supervised!(hd(Dawarich.Redis.child_specs()))
    config = Dawarich.Geocoding.Config.resolve(ScratchRepo)
    {url, _, _} = Dawarich.Geocoding.Query.build(config, {52.0, 13.0}, [], "synthetic")
    Dawarich.Geocoding.FakeHttp.stub(url, 200, Jason.encode!(%{"features" => []}))
    assert ReversePointWorker.perform(%Oban.Job{args: leaf, conf: Oban.config(@oban)}) == :ok
    assert rows("SELECT reverse_geocoded_at IS NOT NULL FROM points WHERE id = 48303") == [[true]]
  end

  test "root replay after first-batch leaves finish drains every accepted continuation user once" do
    f =
      Jason.decode!(File.read!(@fixture))["classes"]["Points::NightlyReverseGeocodingJob"][
        "cases"
      ]
      |> Enum.find(&(&1["id"] == "batches"))

    load_points(f, "batches")
    rows("DELETE FROM points WHERE reverse_geocoded_at IS NULL")

    rows(
      "INSERT INTO points (id,user_id,timestamp,lonlat,created_at,updated_at) " <>
        "SELECT 49000+n,CASE WHEN n <= 1000 THEN 48101 ELSE 48102 END,1791115200+n," <>
        "ST_GeogFromText('POINT(13 52)'),now(),now() FROM generate_series(1,1001) n"
    )

    Ownership.put!(ScratchRepo, NightlyWorker.key(), :oban)
    Ownership.put!(ScratchRepo, "command:geocoding.reverse_point", :oban)
    assert NightlyWorker.run(ScratchRepo, @oban, @slot, env: @env) == :ok

    assert [[next]] =
             rows(
               "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Geocoding.NightlyWorker'"
             )

    assert next["affected_user_ids"] == [48_101]
    rows("UPDATE points SET reverse_geocoded_at=now() WHERE id BETWEEN 49001 AND 50000")
    assert NightlyWorker.run(ScratchRepo, @oban, @slot, env: @env) == :ok
    assert NightlySweep.run(ScratchRepo, @oban, next, env: @env) == :ok
    assert NightlySweep.run(ScratchRepo, @oban, next, env: @env) == :ok

    assert rows(
             "SELECT payload->>'user_id',count(*) FROM phoenix.rails_commands " <>
               "WHERE kind='stats.caches_invalidated' GROUP BY payload->>'user_id' ORDER BY 1"
           ) == [["48101", 1], ["48102", 1]]

    assert rows(
             "SELECT sum(jsonb_array_length(args->'point_ids')) FROM oban.oban_jobs " <>
               "WHERE worker='Dawarich.Geocoding.ReversePointWorker'"
           ) == [[1001]]
  end

  defp continue(env) do
    case rows(
           "SELECT id, args FROM oban.oban_jobs WHERE worker = 'Dawarich.Geocoding.NightlyWorker' AND state = 'available' ORDER BY id LIMIT 1"
         ) do
      [[id, args]] ->
        assert NightlySweep.run(ScratchRepo, @oban, args, env: env) == :ok

        rows(
          "UPDATE oban.oban_jobs SET state = 'completed', completed_at = now() WHERE id = $1",
          [id]
        )

        continue(env)

      [] ->
        :ok
    end
  end
end
