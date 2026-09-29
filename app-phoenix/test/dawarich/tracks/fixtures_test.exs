defmodule Dawarich.Tracks.FixturesTest do
  use ExUnit.Case, async: false

  alias Dawarich.Tracks.TracksFixtures

  @tables ~w[users point_sources imports points tracks track_segments]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
  end

  for name <- TracksFixtures.names() do
    @name name

    test "every fixture loads into the scratch database: #{name}" do
      counts = TracksFixtures.input_counts(@name)
      result = TracksFixtures.load!(Dawarich.Repo, @name)

      assert is_map(result.expected)
      assert is_list(result.call)

      for table <- @tables do
        ids = Map.fetch!(counts, table)

        %{rows: [[count]]} =
          Dawarich.Repo.query!("SELECT count(*) FROM #{table} WHERE id = ANY($1::bigint[])", [ids])

        assert count == length(ids),
               "expected #{length(ids)} #{table} rows for #{@name}, got #{count}"
      end
    end
  end

  test "sequences advance past inserted fixture ids so a fresh INSERT can proceed" do
    Dawarich.Repo.query!("SELECT setval(pg_get_serial_sequence('tracks', 'id'), 1, false)")

    TracksFixtures.load!(Dawarich.Repo, "range_dst")

    %{rows: [[user_id]]} = Dawarich.Repo.query!("SELECT id FROM users ORDER BY id LIMIT 1")
    %{rows: [[max_track_id]]} = Dawarich.Repo.query!("SELECT COALESCE(MAX(id), 0) FROM tracks")

    %{rows: [[track_id]]} =
      Dawarich.Repo.query!(
        "INSERT INTO tracks (user_id, tracker_id, start_at, end_at, original_path, distance, avg_speed, " <>
          "duration, elevation_gain, elevation_loss, elevation_max, elevation_min, created_at, updated_at) " <>
          "VALUES ($1, 'seq-check', now(), now(), " <>
          "ST_GeomFromText('LINESTRING(12.3731 51.3397, 12.3741 51.3407)', 4326), 0, 0, 0, 0, 0, 0, 0, now(), " <>
          "now()) RETURNING id",
        [user_id]
      )

    assert track_id > max_track_id
  end
end
