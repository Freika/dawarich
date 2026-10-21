defmodule Dawarich.Tracks.ImportReprocessorTest do
  use Dawarich.JobsCase
  alias Dawarich.Test.{ActivityBackfillFixtures, ApiGolden}
  alias Dawarich.Tracks.{ImportReprocessor, Reprocessor, Settings, Store}
  alias Dawarich.Transportation.Segments
  alias __MODULE__.DetectorFailureRepo

  @dir Path.expand("../../fixtures/a12rel", __DIR__)
  @now ~U[2026-01-15 23:30:00.000000Z]

  setup do
    foreign_keys =
      rows(
        "SELECT conname,pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid='points'::regclass AND confrelid='tracks'::regclass"
      )

    sequences =
      Map.new(
        ~w(track_segments tracks),
        &{&1, rows("SELECT last_value,is_called FROM #{&1}_id_seq")}
      )

    on_exit(fn ->
      rows("DROP TRIGGER IF EXISTS a12rel_track_failure ON track_segments")
      rows("DROP FUNCTION IF EXISTS a12rel_track_failure()")
      cleanup()

      for [name, definition] <- foreign_keys do
        if rows("SELECT count(*) FROM pg_constraint WHERE conname=$1", [name]) == [[0]],
          do: rows("ALTER TABLE points ADD CONSTRAINT #{name} #{definition}")
      end

      for {table, [[value, called]]} <- sequences do
        rows("SELECT setval('#{table}_id_seq',$1,$2)", [value, called])
      end
    end)

    :ok
  end

  test "import reprocessing counts each distinct existing track and continues after rollback" do
    for name <-
          ~w(selection preservation empty fallback sql_failure unchanged nil_user deleted_user) do
      profile = fixture(name)
      seed!(profile)
      rows("DELETE FROM phoenix.rails_commands WHERE kind='tracks_changed'")

      repo =
        if name in ~w(fallback sql_failure unchanged), do: DetectorFailureRepo, else: ScratchRepo

      caller = self()

      opts = [
        now: @now,
        report: fn id, error -> send(caller, {:track_error, id, error.__struct__}) end
      ]

      opts =
        if name == "empty", do: Keyword.put(opts, :detector, fn _, _, _ -> [] end), else: opts

      Process.put(:a12rel_track_failure, name == "sql_failure")

      assert ImportReprocessor.run(repo, 987_101, opts) == profile["attempted"]

      for id <- 56_201..56_204 do
        assert_track(profile["after"], id)
        assert_segments(profile["after"], id)
      end

      assert_full_snapshot(profile["after"])
      assert committed_snapshot() == snapshot()

      commands = rows("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id")

      assert Enum.map(commands, fn [kind, payload] ->
               assert kind == "tracks_changed"
               assert payload["created"] == []
               assert payload["destroyed"] == []
               [payload["user_id"], payload["min_ts"], payload["max_ts"]]
             end) == profile["tile_ranges"]

      assert Enum.flat_map(commands, fn [_, payload] -> payload["updated"] end) ==
               Enum.map(profile["broadcasts"], & &1["payload"]["track"]["id"])

      assert rows("SELECT count(*) FROM phoenix.rails_commands WHERE kind='transport_progress'") ==
               [[0]]

      if name == "sql_failure" do
        assert_receive {:track_error, 56_202, Postgrex.Error}
        Process.delete(:a12rel_track_failure)
        assert ImportReprocessor.run(repo, 987_101, opts) == profile["retry"]["attempted"]
        assert_full_snapshot(profile["retry"]["after"])
      else
        refute_receive {:track_error, _, _}, 0
      end
    end

    profile = fixture("selection")
    seed!(profile)

    [[constraint, _]] =
      rows(
        "SELECT conname,pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid='points'::regclass AND confrelid='tracks'::regclass"
      )

    rows("ALTER TABLE points DROP CONSTRAINT #{constraint}")
    rows("UPDATE points SET track_id=56999 WHERE id=56398")
    assert ImportReprocessor.run(ScratchRepo, 987_101, now: @now) == 3
    assert ImportReprocessor.run(ScratchRepo, 999_999, now: @now) == 0
  end

  test "import batch fallback preserves manual and source segments while single reset stays strict" do
    for name <- ["selection", "preservation", "fallback"] do
      profile = fixture(name)
      seed!(profile)
      repo = if name == "fallback", do: DetectorFailureRepo, else: ScratchRepo
      user = Settings.find(ScratchRepo, 987_001)
      track = Store.get(ScratchRepo, 56_201)

      assert {:ok, _} =
               repo.transaction(fn ->
                 Reprocessor.reprocess!(repo, user, track, @now, fallback: true)
               end)

      assert_track(profile["after"], 56_201)
      assert_segments(profile["after"], 56_201)
    end

    profile = fixture("fallback")
    seed!(profile)
    before = snapshot()

    assert_raise RuntimeError, "A12rel feature failure", fn ->
      DetectorFailureRepo.transaction(fn ->
        Reprocessor.reprocess!(
          DetectorFailureRepo,
          Settings.find(ScratchRepo, 987_001),
          Store.get(ScratchRepo, 56_201),
          @now
        )
      end)
    end

    assert snapshot() == before

    profile = fixture("preservation")
    seed!(profile)
    rows("UPDATE users SET deleted_at=$1 WHERE id=987001", [DateTime.to_naive(@now)])
    assert Settings.find(ScratchRepo, 987_001) == nil

    assert {:ok, _} =
             ScratchRepo.transaction(fn ->
               Reprocessor.reprocess!(ScratchRepo, nil, Store.get(ScratchRepo, 56_201), @now,
                 fallback: true
               )
             end)

    assert_segments(profile["after"], 56_201)
  end

  defmodule DetectorFailureRepo do
    defdelegate transaction(fun), to: Dawarich.ScratchRepo
    defdelegate rollback(reason), to: Dawarich.ScratchRepo

    def query!(sql, params, opts \\ []) do
      cond do
        String.contains?(sql, "p.id AS point_id") ->
          raise("A12rel feature failure")

        Process.get(:a12rel_track_failure) &&
          String.starts_with?(sql, "INSERT INTO track_segments") && hd(params) == 56_202 ->
          Dawarich.ScratchRepo.query!(
            "UPDATE track_segments SET a12rel_missing_column=1",
            [],
            opts
          )

        true ->
          Dawarich.ScratchRepo.query!(sql, params, opts)
      end
    end
  end

  defp fixture(name) do
    @dir
    |> Path.join("track_batches.json")
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("cases")
    |> Enum.find(&(&1["id"] == name))
  end

  defp seed!(profile) do
    cleanup()
    source = ActivityBackfillFixtures.profile("semantic")

    ActivityBackfillFixtures.seed!(%{
      source
      | "before" => Map.put(source["before"], "points", [])
    })

    rows("UPDATE users SET settings=$1 WHERE id=987001", [
      %{"enabled_transportation_modes" => ["walking", "cycling"]}
    ])

    if profile["id"] in ["nil_user", "deleted_user"],
      do: rows("UPDATE users SET deleted_at=$1 WHERE id=987001", [DateTime.to_naive(@now)])

    for row <- profile["before"]["tracks"] do
      row =
        row
        |> then(&ApiGolden.column_defaults("tracks", &1))
        |> Map.put("original_path", row["ewkb"])
        |> Map.delete("ewkb")
        |> Map.update!("dominant_mode", &Segments.mode_to_int/1)

      ApiGolden.insert!("tracks", row, ScratchRepo)
    end

    for row <- profile["before"]["segments"],
        do: ApiGolden.insert!("track_segments", row, ScratchRepo)

    for row <- profile["points"] do
      row = row |> Map.put("lonlat", row["ewkb"]) |> Map.delete("ewkb")
      ApiGolden.insert!("points", row, ScratchRepo)
    end

    rows("SELECT setval('track_segments_id_seq',56500,false)")
  end

  defp cleanup do
    rows("DELETE FROM points WHERE user_id=987001")
    rows("DELETE FROM track_segments WHERE track_id BETWEEN 56201 AND 56204")
    rows("DELETE FROM tracks WHERE id BETWEEN 56201 AND 56204")
    ActivityBackfillFixtures.cleanup()
  end

  defp snapshot do
    for {table, column} <- [{"tracks", "original_path"}, {"track_segments", "path"}],
        do:
          rows(
            "SELECT to_jsonb(t) || jsonb_build_object('#{column}',encode(ST_AsEWKB(#{column}),'hex')) FROM #{table} t ORDER BY id"
          )
  end

  defp committed_snapshot do
    ScratchRepo.checkout(fn ->
      [[first]] = rows("SELECT pg_backend_pid()")

      {second, data} =
        Task.async(fn ->
          ScratchRepo.checkout(fn ->
            [[pid]] = rows("SELECT pg_backend_pid()")
            {pid, snapshot()}
          end)
        end)
        |> Task.await()

      assert first != second
      data
    end)
  end

  defp assert_full_snapshot(expected) do
    [tracks, segments] = snapshot()
    actual_tracks = Enum.map(tracks, fn [row] -> normalize(row) end)

    expected_tracks =
      Enum.map(expected["tracks"], fn row ->
        row
        |> then(&ApiGolden.column_defaults("tracks", &1))
        |> Map.put("original_path", row["ewkb"])
        |> Map.delete("ewkb")
        |> Map.update!("dominant_mode", &Segments.mode_to_int/1)
        |> normalize()
      end)

    assert actual_tracks == expected_tracks

    assert Enum.map(segments, fn [row] -> normalize(row) end) ==
             expected["segments"] |> Enum.sort_by(& &1["id"]) |> Enum.map(&normalize/1)
  end

  defp normalize(row) do
    Map.new(row, fn
      {key, stamp}
      when key in ~w(created_at updated_at start_at end_at corrected_at) and is_binary(stamp) ->
        parsed =
          case DateTime.from_iso8601(stamp) do
            {:ok, time, _} -> time
            _ -> stamp |> NaiveDateTime.from_iso8601!() |> DateTime.from_naive!("Etc/UTC")
          end

        {key, DateTime.to_unix(parsed, :microsecond)}

      {key, geometry} when key in ~w(path original_path) and is_binary(geometry) ->
        {key, String.downcase(geometry)}

      pair ->
        pair
    end)
  end

  defp assert_track(expected, id) do
    track = Enum.find(expected["tracks"], &(&1["id"] == id))
    {:ok, stamp, _} = DateTime.from_iso8601(track["updated_at"])

    assert rows("SELECT dominant_mode,lock_version,updated_at FROM tracks WHERE id=$1", [id]) == [
             [
               Segments.mode_to_int(track["dominant_mode"]),
               track["lock_version"],
               DateTime.to_naive(stamp)
             ]
           ]
  end

  defp assert_segments(expected, id) do
    fields =
      ~w(id track_id transportation_mode source distance duration avg_speed max_speed confidence confidence_score start_index end_index)

    actual =
      rows("SELECT to_jsonb(s) FROM track_segments s WHERE track_id=$1 ORDER BY id", [id])
      |> Enum.map(fn [row] -> Map.take(row, fields) end)

    assert actual ==
             expected["segments"]
             |> Enum.filter(&(&1["track_id"] == id))
             |> Enum.map(&Map.take(&1, fields))

    for row <- expected["segments"], row["track_id"] == id do
      {:ok, created, _} = DateTime.from_iso8601(row["created_at"])
      {:ok, updated, _} = DateTime.from_iso8601(row["updated_at"])

      assert rows("SELECT created_at,updated_at FROM track_segments WHERE id=$1", [row["id"]]) ==
               [[DateTime.to_naive(created), DateTime.to_naive(updated)]]
    end
  end
end
