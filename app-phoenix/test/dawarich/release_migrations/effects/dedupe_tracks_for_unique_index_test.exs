defmodule Dawarich.ReleaseMigrations.Effects.DedupeTracksForUniqueIndexTest do
  use Dawarich.ScratchCase

  alias Dawarich.ReleaseMigrations.Effects.DedupeTracksForUniqueIndex

  setup do
    scratch_sql!("""
    CREATE TABLE users (id bigserial PRIMARY KEY, deleted_at timestamp);
    CREATE TABLE tracks (id bigserial PRIMARY KEY, user_id bigint NOT NULL REFERENCES users (id), start_at timestamp NOT NULL, end_at timestamp NOT NULL);
    CREATE TABLE track_segments (id bigserial PRIMARY KEY, track_id bigint NOT NULL REFERENCES tracks (id));
    CREATE TABLE points (id bigserial PRIMARY KEY, track_id bigint);
    INSERT INTO users (deleted_at) VALUES (NULL), (NULL);
    """)

    :ok
  end

  test "keeps the highest id per key, deletes the losers' segments and detaches their points" do
    scratch_sql!("""
    INSERT INTO tracks (user_id, start_at, end_at) VALUES
      (1, '2026-01-02 00:00', '2026-01-02 01:00'), (1, '2026-01-02 00:00', '2026-01-02 01:00'),
      (1, '2026-01-02 00:00', '2026-01-02 02:00'), (2, '2026-01-02 00:00', '2026-01-02 01:00');
    INSERT INTO track_segments (track_id) VALUES (1), (1), (2), (3), (4);
    INSERT INTO points (track_id) VALUES (1), (2), (2), (3), (4), (NULL);
    """)

    DedupeTracksForUniqueIndex.run(ScratchRepo)

    assert column("SELECT id FROM tracks ORDER BY id") == [2, 3, 4]
    assert column("SELECT track_id FROM track_segments ORDER BY id") == [2, 3, 4]
    assert column("SELECT track_id FROM points ORDER BY id") == [nil, 2, 2, 3, 4, nil]
  end

  test "collapses a three-way duplicate onto its newest track" do
    scratch_sql!("""
    INSERT INTO tracks (user_id, start_at, end_at) VALUES
      (2, '2026-01-03 00:00', '2026-01-03 01:00'), (2, '2026-01-03 00:00', '2026-01-03 01:00'),
      (2, '2026-01-03 00:00', '2026-01-03 01:00');
    INSERT INTO track_segments (track_id) VALUES (3), (1), (2);
    INSERT INTO points (track_id) VALUES (1), (2), (3);
    """)

    DedupeTracksForUniqueIndex.run(ScratchRepo)

    assert column("SELECT id FROM tracks ORDER BY id") == [3]
    assert column("SELECT track_id FROM track_segments ORDER BY id") == [3]
    assert column("SELECT track_id FROM points ORDER BY id") == [nil, nil, 3]
  end

  test "dedupes a soft-deleted user's tracks too, as User.unscoped.find_by does" do
    scratch_sql!("""
    UPDATE users SET deleted_at = '2026-01-04 00:00' WHERE id = 1;
    INSERT INTO tracks (user_id, start_at, end_at) VALUES
      (1, '2026-01-02 00:00', '2026-01-02 01:00'), (1, '2026-01-02 00:00', '2026-01-02 01:00'),
      (2, '2026-01-02 00:00', '2026-01-02 01:00'), (2, '2026-01-02 00:00', '2026-01-02 01:00');
    INSERT INTO track_segments (track_id) VALUES (1), (3);
    INSERT INTO points (track_id) VALUES (1), (3);
    """)

    DedupeTracksForUniqueIndex.run(ScratchRepo)

    assert column("SELECT id FROM tracks ORDER BY id") == [2, 4]
    assert column("SELECT track_id FROM track_segments ORDER BY id") == []
    assert column("SELECT track_id FROM points ORDER BY id") == [nil, nil]
  end

  test "changes nothing when no key is duplicated" do
    scratch_sql!("""
    INSERT INTO tracks (user_id, start_at, end_at) VALUES
      (1, '2026-01-02 00:00', '2026-01-02 01:00'), (1, '2026-01-02 00:00', '2026-01-02 02:00'),
      (2, '2026-01-02 00:00', '2026-01-02 01:00');
    INSERT INTO track_segments (track_id) VALUES (1), (2), (3);
    INSERT INTO points (track_id) VALUES (1), (2), (3);
    """)

    DedupeTracksForUniqueIndex.run(ScratchRepo)

    assert column("SELECT id FROM tracks ORDER BY id") == [1, 2, 3]
    assert column("SELECT track_id FROM track_segments ORDER BY id") == [1, 2, 3]
    assert column("SELECT track_id FROM points ORDER BY id") == [1, 2, 3]
  end

  defp column(sql), do: ScratchRepo.query!(sql, [], log: false).rows |> List.flatten()
end
