defmodule Dawarich.Tracks.ImportReprocessorTest do
  use Dawarich.JobsCase
  alias Dawarich.Test.{ActivityBackfillFixtures, ApiGolden}
  alias Dawarich.Tracks.{Reprocessor, Settings, Store}
  alias Dawarich.Transportation.Segments
  alias __MODULE__.DetectorFailureRepo

  @dir Path.expand("../../fixtures/a12rel", __DIR__)
  @now ~U[2026-01-15 23:30:00.000000Z]

  setup do
    sequences =
      Map.new(
        ~w(track_segments tracks),
        &{&1, rows("SELECT last_value,is_called FROM #{&1}_id_seq")}
      )

    on_exit(fn ->
      cleanup()

      for {table, [[value, called]]} <- sequences do
        rows("SELECT setval('#{table}_id_seq',$1,$2)", [value, called])
      end
    end)

    :ok
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
      if String.contains?(sql, "p.id AS point_id"),
        do: raise("A12rel feature failure"),
        else: Dawarich.ScratchRepo.query!(sql, params, opts)
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
    for table <- ~w(tracks track_segments),
        do: rows("SELECT to_jsonb(t) FROM #{table} t ORDER BY id")
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
