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

  test "nightly geocoding publishes every source pending point once with force and bounded leaf IDs" do
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

      for id <- expected, do: State.claim(ScratchRepo, "geocode:enq:Point:#{id}", 3600)
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
        assert payload["force"] == true
        assert length(payload["point_ids"]) <= 100
        data = Map.take(payload, ~w(user_id point_ids force))
        assert {:ok, _} = ReversePointWorker.args_from_command(1, data)

        assert rows(
                 "SELECT count(*) FROM points WHERE id = ANY($1::bigint[]) AND user_id <> $2",
                 [payload["point_ids"], payload["user_id"]]
               ) == [[0]]
      end

      assert rows("SELECT count(*) FROM phoenix.once_claims WHERE key LIKE 'geocode:enq:Point:%'") ==
               [[0]]

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
