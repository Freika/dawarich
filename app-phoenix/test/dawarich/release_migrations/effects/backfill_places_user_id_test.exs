defmodule Dawarich.ReleaseMigrations.Effects.BackfillPlacesUserIdTest do
  use Dawarich.ScratchCase

  alias Dawarich.ReleaseMigrations.Effects.BackfillPlacesUserId
  alias Dawarich.ReleaseMigrations.V1_14_0

  @remaining "[Migration] places_user_id_backfill remaining=2. List them with: SELECT id FROM places " <>
               "WHERE user_id IS NULL; assign an owner to those places or delete them, then migrate again"

  setup do
    scratch_sql!("""
    CREATE TABLE places (id bigserial PRIMARY KEY, name varchar NOT NULL, user_id bigint, updated_at timestamp NOT NULL);
    CREATE TABLE visits (id bigserial PRIMARY KEY, user_id bigint NOT NULL, place_id bigint REFERENCES places (id), started_at timestamp NOT NULL);
    CREATE TABLE place_visits (id bigserial PRIMARY KEY, place_id bigint NOT NULL REFERENCES places (id), visit_id bigint NOT NULL REFERENCES visits (id));
    """)

    :ok
  end

  test "gives each place to the user with the most visits, counting place_visits and visits.place_id together" do
    places(~w[counted union double])

    scratch_sql!("""
    INSERT INTO visits (user_id, place_id, started_at) VALUES
      (7, 1, '2026-01-01 10:00'), (7, 1, '2026-01-02 10:00'), (5, 1, '2026-01-09 10:00'),
      (5, 2, '2026-01-01 10:00'), (7, NULL, '2026-01-01 10:00'), (7, NULL, '2026-01-02 10:00'),
      (5, 3, '2026-01-01 10:00'), (7, 3, '2026-01-02 10:00'), (8, NULL, '2026-01-03 10:00');
    INSERT INTO place_visits (place_id, visit_id) VALUES (2, 5), (2, 6), (3, 7), (3, 9);
    """)

    BackfillPlacesUserId.run(ScratchRepo)

    assert owners() == [{"counted", 7}, {"union", 7}, {"double", 5}]
  end

  test "breaks a visit-count tie by the newest visit, then by the smallest user id" do
    places(~w[newest smallest])

    scratch_sql!("""
    INSERT INTO visits (user_id, place_id, started_at) VALUES
      (4, 1, '2026-01-01 10:00'), (9, 1, '2026-01-05 10:00'),
      (9, 2, '2026-01-05 10:00'), (4, 2, '2026-01-05 10:00');
    """)

    BackfillPlacesUserId.run(ScratchRepo)

    assert owners() == [{"newest", 9}, {"smallest", 4}]
  end

  test "deletes the places nobody visited and leaves owned places alone" do
    places(~w[visited unvisited])

    scratch_sql!("""
    INSERT INTO places (name, user_id, updated_at) VALUES ('owned', 3, '2026-01-01 00:00');
    INSERT INTO visits (user_id, place_id, started_at) VALUES (6, 1, '2026-01-01 10:00');
    """)

    BackfillPlacesUserId.run(ScratchRepo)

    assert owners() == [{"visited", 6}, {"owned", 3}]

    assert column("SELECT updated_at::text FROM places WHERE name = 'owned'") == [
             "2026-01-01 00:00:00"
           ]
  end

  test "works in id-ordered batches and stops at the first batch that makes no progress" do
    places(~w[first stuck1 stuck2 last])

    scratch_sql!("""
    CREATE RULE keep_places AS ON DELETE TO places DO INSTEAD NOTHING;
    INSERT INTO visits (user_id, place_id, started_at) VALUES (2, 1, '2026-01-01 10:00'), (3, 4, '2026-01-01 10:00');
    """)

    BackfillPlacesUserId.run(ScratchRepo, 2)

    assert owners() == [{"first", 2}, {"stuck1", nil}, {"stuck2", nil}, {"last", nil}]

    BackfillPlacesUserId.run(ScratchRepo, 4)

    assert owners() == [{"first", 2}, {"stuck1", nil}, {"stuck2", nil}, {"last", 3}]
  end

  test "20260815100001 drains the places, then validates and sets NOT NULL" do
    places(~w[visited unvisited])

    scratch_sql!(
      "INSERT INTO visits (user_id, place_id, started_at) VALUES (6, 1, '2026-01-01 10:00')"
    )

    not_valid_check()

    step().(ScratchRepo)

    assert owners() == [{"visited", 6}]

    assert column(
             "SELECT attnotnull FROM pg_attribute WHERE attrelid = 'places'::regclass AND attname = 'user_id'"
           ) == [true]

    assert column(
             "SELECT conname FROM pg_constraint WHERE conrelid = 'places'::regclass AND contype = 'c'"
           ) == []
  end

  test "20260815100001 raises Rails' remaining message and keeps what the drain committed" do
    places(~w[visited stuck1 stuck2])

    scratch_sql!("""
    CREATE RULE keep_places AS ON DELETE TO places DO INSTEAD NOTHING;
    INSERT INTO visits (user_id, place_id, started_at) VALUES (6, 1, '2026-01-01 10:00');
    """)

    not_valid_check()

    assert_raise RuntimeError, @remaining, fn -> step().(ScratchRepo) end
    assert owners() == [{"visited", 6}, {"stuck1", nil}, {"stuck2", nil}]

    assert column(
             "SELECT attnotnull FROM pg_attribute WHERE attrelid = 'places'::regclass AND attname = 'user_id'"
           ) == [false]
  end

  defp places(names) do
    for name <- names do
      ScratchRepo.query!(
        "INSERT INTO places (name, updated_at) VALUES ($1, '2026-01-01 00:00')",
        [name],
        log: false
      )
    end
  end

  defp not_valid_check do
    scratch_sql!(
      "ALTER TABLE places ADD CONSTRAINT places_user_id_not_null CHECK (user_id IS NOT NULL) NOT VALID"
    )
  end

  defp step do
    {"20260815100001", fun, transaction: false} =
      List.keyfind(V1_14_0.steps(), "20260815100001", 0)

    fun
  end

  defp owners do
    ScratchRepo.query!("SELECT name, user_id FROM places ORDER BY id", [], log: false).rows
    |> Enum.map(&List.to_tuple/1)
  end

  defp column(sql), do: ScratchRepo.query!(sql, [], log: false).rows |> List.flatten()
end
