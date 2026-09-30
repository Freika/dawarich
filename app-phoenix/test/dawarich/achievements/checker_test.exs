defmodule Dawarich.Achievements.CheckerTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.Achievements.{Checker, Registry}

  defmodule RacingAwardRepo do
    @moduledoc false
    alias Dawarich.ScratchRepo

    def transaction(fun), do: ScratchRepo.transaction(fun)

    def query!(sql, params, opts) do
      result = ScratchRepo.query!(sql, params, opts)

      if String.starts_with?(sql, "SELECT achievement_key FROM user_achievements") do
        ScratchRepo.query!(
          "INSERT INTO user_achievements (user_id, achievement_key, earned_at, metadata, created_at, updated_at) VALUES ($1, 'country_lu', now(), '{}', now(), now())",
          params,
          log: false
        )
      end

      result
    end
  end

  defmodule ScanTimeoutRepo do
    @moduledoc false
    alias Dawarich.ScratchRepo

    def transaction(fun), do: ScratchRepo.transaction(fun)

    def query!(sql, params, opts) do
      if sql =~ "FROM points", do: send(self(), {:points_scan, sql, opts[:timeout]})
      ScratchRepo.query!(sql, params, opts)
    end
  end

  @fixture Path.expand("../../fixtures/achievements/check.json", __DIR__)

  setup do
    rows("TRUNCATE public.countries, public.regions RESTART IDENTITY")
    fixture = @fixture |> File.read!() |> Jason.decode!()
    %{fixture: fixture, uid: fixture["user"]["id"], steps: fixture["steps"]}
  end

  defp load!(fixture) do
    rows(
      "INSERT INTO users (id, email, settings, created_at, updated_at) SELECT id, email, settings, created_at, updated_at FROM json_populate_record(NULL::users, $1)",
      [fixture["user"]]
    )

    for country <- fixture["countries"],
        do:
          rows(
            "INSERT INTO countries (id, iso_a2, iso_a3, name, geom, created_at, updated_at) SELECT id, iso_a2, iso_a3, name, geom, created_at, updated_at FROM json_populate_record(NULL::countries, $1)",
            [country]
          )

    for region <- fixture["regions"],
        do:
          rows(
            "INSERT INTO regions (id, code, geom, created_at, updated_at) SELECT id, code, geom, created_at, updated_at FROM json_populate_record(NULL::regions, $1)",
            [region]
          )
  end

  defp apply!(uid, step) do
    for point <- step["points"],
        do:
          rows("INSERT INTO points SELECT * FROM json_populate_record(NULL::points, $1)", [point])

    rows("UPDATE points SET anomaly = true WHERE user_id = $1 AND timestamp = ANY($2)", [
      uid,
      step["anomaly_timestamps"]
    ])
  end

  defp run!(uid, step, hook \\ fn _stage -> :ok end) do
    apply!(uid, step)
    Checker.run(ScratchRepo, uid, step["notify"], step["oldest"], hook)
  end

  defp replay!(uid, steps), do: for(step <- steps, do: :ok = run!(uid, step))

  defp snapshot(uid) do
    state =
      case rows(
             "SELECT state FROM achievement_progresses WHERE user_id = $1 AND achievement_key = 'exploration'",
             [uid]
           ) do
        [[state]] -> Map.update(state, "earned", [], &(&1 |> Map.keys() |> Enum.sort()))
        [] -> nil
      end

    %{
      "state" => state,
      "events" =>
        Enum.sort(
          rows("SELECT kind, key FROM achievement_unlock_events WHERE user_id = $1", [uid])
        ),
      "awards" =>
        rows("SELECT achievement_key FROM user_achievements WHERE user_id = $1", [uid])
        |> List.flatten()
        |> Enum.sort(),
      "notifications" =>
        Enum.sort(
          rows("SELECT kind, title, content FROM notifications WHERE user_id = $1", [uid])
        )
    }
  end

  defp counts do
    rows(
      "SELECT (SELECT count(*) FROM notifications), (SELECT count(*) FROM phoenix.notification_events), (SELECT count(*) FROM achievement_unlock_events)"
    )
  end

  test "step 1: a first computation earns silently", %{fixture: fixture, uid: uid, steps: steps} do
    load!(fixture)

    assert run!(uid, Enum.at(steps, 0)) == :ok

    assert snapshot(uid) == Enum.at(steps, 0)["expected"]
    assert %{"notifications" => [], "events" => [], "awards" => ["country_lu"]} = snapshot(uid)
  end

  test "step 2: an incremental check announces the new region in the user's locale", %{
    fixture: fixture,
    uid: uid,
    steps: steps
  } do
    load!(fixture)
    replay!(uid, Enum.take(steps, 1))

    assert run!(uid, Enum.at(steps, 1)) == :ok

    assert snapshot(uid) == Enum.at(steps, 1)["expected"]
    assert String.ends_with?(snapshot(uid)["state"]["inserted_through"], ".500000Z")
  end

  test "step 3: more than five new regions collapse into one digest notification", %{
    fixture: fixture,
    uid: uid,
    steps: steps
  } do
    load!(fixture)
    replay!(uid, Enum.take(steps, 2))
    [[before, _, _]] = counts()

    assert run!(uid, Enum.at(steps, 2)) == :ok

    assert snapshot(uid) == Enum.at(steps, 2)["expected"]
    assert [[after_run, after_run, _]] = counts()
    assert after_run == before + 1
    assert String.ends_with?(snapshot(uid)["state"]["inserted_through"], ".000000Z")
  end

  test "step 4: an older timestamp recomputes dwell from scratch and keeps earned codes", %{
    fixture: fixture,
    uid: uid,
    steps: steps
  } do
    load!(fixture)
    replay!(uid, Enum.take(steps, 3))

    assert run!(uid, Enum.at(steps, 3)) == :ok

    assert snapshot(uid) == Enum.at(steps, 3)["expected"]
    refute Map.has_key?(snapshot(uid)["state"]["dwell"], "DE-ST")
    assert "DE-ST" in snapshot(uid)["state"]["earned"]
  end

  test "every points scan runs without a query timeout, as Rails sets no statement timeout", %{
    fixture: fixture,
    uid: uid,
    steps: steps
  } do
    load!(fixture)
    replay!(uid, Enum.take(steps, 3))
    step = Enum.at(steps, 3)
    apply!(uid, step)

    assert Checker.run(ScanTimeoutRepo, uid, step["notify"], step["oldest"]) == :ok

    scans = collect_points_scans([])
    assert Enum.any?(scans, fn {sql, _} -> sql =~ "LEAD(" end)
    assert Enum.any?(scans, fn {sql, _} -> sql =~ ~s|max("timestamp")| end)
    assert Enum.all?(scans, fn {_, timeout} -> timeout == :infinity end)
  end

  defp collect_points_scans(acc) do
    receive do
      {:points_scan, sql, timeout} -> collect_points_scans([{sql, timeout} | acc])
    after
      0 -> acc
    end
  end

  test "a second run of the same step announces nothing and writes no event", %{
    fixture: fixture,
    uid: uid,
    steps: steps
  } do
    load!(fixture)
    replay!(uid, Enum.take(steps, 2))
    before = counts()
    step = Enum.at(steps, 1)
    oldest = step["points"] |> Enum.map(& &1["timestamp"]) |> Enum.min()

    assert Checker.run(ScratchRepo, uid, true, nil) == :ok
    assert counts() == before
    assert Checker.run(ScratchRepo, uid, true, oldest) == :ok
    assert counts() == before
    assert snapshot(uid) == step["expected"]
  end

  test "a concurrent commit is not double counted: the compare-and-set retries once and settles",
       %{fixture: fixture, uid: uid, steps: steps} do
    load!(fixture)
    replay!(uid, Enum.take(steps, 2))
    apply!(uid, Enum.at(steps, 2))
    first = :atomics.new(1, [])

    hook = fn :before_commit ->
      if :atomics.add_get(first, 1, 1) == 1, do: :ok = Checker.run(ScratchRepo, uid, true, nil)
      :ok
    end

    assert Checker.run(ScratchRepo, uid, true, nil, hook) == :ok

    assert :atomics.get(first, 1) == 1
    assert snapshot(uid) == Enum.at(steps, 2)["expected"]
  end

  test "a concurrent commit that moves only the cursor is not double counted either", %{
    fixture: fixture,
    uid: uid,
    steps: steps
  } do
    load!(fixture)
    replay!(uid, Enum.take(steps, 2))
    %{"cursor" => cursor, "inserted_through" => inserted} = snapshot(uid)["state"]
    %{"id" => de} = Enum.find(fixture["countries"], &(&1["iso_a2"] == "DE"))

    rows(
      "INSERT INTO points (user_id, timestamp, lonlat, country_id, anomaly, created_at, updated_at) SELECT $1, $2 + g * 300, ST_SetSRID(ST_MakePoint(12.15, 51.15), 4326), $3, false, '2026-06-02 10:00:00', '2026-06-02 10:00:00' FROM generate_series(0, 8) g",
      [uid, cursor + 3600, de]
    )

    [[before, _, _]] = counts()
    first = :atomics.new(1, [])

    hook = fn :before_commit ->
      if :atomics.add_get(first, 1, 1) == 1,
        do: :ok = Checker.run(ScratchRepo, uid, true, cursor + 3600)

      :ok
    end

    assert Checker.run(ScratchRepo, uid, true, cursor + 3600, hook) == :ok

    assert %{"cursor" => moved, "inserted_through" => ^inserted, "dwell" => %{"DE-TH" => 2400}} =
             snapshot(uid)["state"]

    assert moved == cursor + 3600 + 2400
    assert [[after_run, _, _]] = counts()
    assert after_run == before + 1
  end

  test "a watermark read back with fewer fraction digits is rewritten with six, as Ruby's iso8601(6)",
       %{fixture: fixture, uid: uid, steps: steps} do
    load!(fixture)
    replay!(uid, Enum.take(steps, 2))

    for {step, stored, written} <- [
          {nil, "2026-06-03T10:00:00.5Z", "2026-06-03T10:00:00.500000Z"},
          {2, "2026-06-04T10:00:00Z", "2026-06-04T10:00:00.000000Z"}
        ] do
      if step, do: :ok = run!(uid, Enum.at(steps, step))

      rows(
        "UPDATE achievement_progresses SET state = jsonb_set(state, '{inserted_through}', to_jsonb($2::text)) WHERE user_id = $1",
        [uid, stored]
      )

      assert Checker.run(ScratchRepo, uid, true, nil) == :ok
      assert snapshot(uid)["state"]["inserted_through"] == written
    end
  end

  test "a missing or deleted user is :missing and writes nothing", %{
    fixture: fixture,
    uid: uid,
    steps: steps
  } do
    load!(fixture)
    apply!(uid, Enum.at(steps, 0))
    rows("UPDATE users SET deleted_at = now() WHERE id = $1", [uid])

    assert Checker.run(ScratchRepo, 0, true, nil) == :missing
    assert Checker.run(ScratchRepo, uid, true, nil) == :missing

    assert rows(
             "SELECT (SELECT count(*) FROM achievement_progresses), (SELECT count(*) FROM user_achievements), (SELECT count(*) FROM achievement_unlock_events), (SELECT count(*) FROM notifications)"
           ) == [[0, 0, 0, 0]]
  end

  test "an award created concurrently is not announced", %{
    fixture: fixture,
    uid: uid,
    steps: steps
  } do
    load!(fixture)
    apply!(uid, Enum.at(steps, 0))

    rows(
      "INSERT INTO achievement_progresses (user_id, achievement_key, state, sharing_enabled, created_at, updated_at) VALUES ($1, 'exploration', '{\"calculation_version\": 3}', false, now(), now())",
      [uid]
    )

    assert Checker.run(RacingAwardRepo, uid, true, nil) == :ok

    {:ok, completion} =
      Dawarich.I18n.t("de", "achievements.notifications.completion_title", %{
        "achievement" => Registry.find("country_lu").names["de"]
      })

    titles = rows("SELECT title FROM notifications WHERE user_id = $1", [uid]) |> List.flatten()
    assert titles != []
    refute completion in titles

    assert rows("SELECT achievement_key FROM user_achievements WHERE user_id = $1", [uid]) == [
             ["country_lu"]
           ]
  end

  test "threshold_seconds follows Ruby's to_i on the setting" do
    assert Checker.threshold_seconds(%{}) == 3600
    assert Checker.threshold_seconds(%{"min_minutes_spent_in_city" => "45abc"}) == 2700
    assert Checker.threshold_seconds(%{"min_minutes_spent_in_city" => nil}) == 3600
    assert Checker.threshold_seconds(%{"min_minutes_spent_in_city" => 12.9}) == 720
    assert Checker.threshold_seconds(nil) == 3600
  end

  test "merged_state keeps unrelated keys, drops point_id_cursor and sorts new codes" do
    state = %{
      "point_id_cursor" => 5,
      "celebrated" => %{"country_lu" => true},
      "dwell" => %{"A" => 100, "B" => 9000},
      "earned" => %{"B" => "2026-06-01T00:00:00Z"}
    }

    deltas = %{"C" => 2000, "A" => 1700, "B" => 5, "D" => 10}

    assert {merged, ["A", "C"]} =
             Checker.merged_state(state, deltas, false, 9, "i", 1800, "2026-06-02T00:00:00Z")

    assert merged == %{
             "celebrated" => %{"country_lu" => true},
             "cursor" => 9,
             "inserted_through" => "i",
             "dwell" => %{"A" => 1800, "B" => 9005, "C" => 2000, "D" => 10},
             "earned" => %{
               "A" => "2026-06-02T00:00:00Z",
               "B" => "2026-06-01T00:00:00Z",
               "C" => "2026-06-02T00:00:00Z"
             },
             "threshold_seconds" => 1800,
             "calculation_version" => 3
           }

    assert {%{"dwell" => dwell}, ["C"]} =
             Checker.merged_state(state, deltas, true, 9, "i", 1800, "now")

    assert dwell == deltas
  end
end
