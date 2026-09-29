defmodule Dawarich.ReleaseMigrations.V1_11_0Test do
  use Dawarich.ScratchCase

  alias Dawarich.ReleaseMigrations.V1_11_0

  setup do
    scratch_sql!("""
    CREATE TABLE visits (id bigserial PRIMARY KEY, user_id bigint NOT NULL, started_at timestamp NOT NULL, place_id bigint);
    CREATE TABLE points (id bigserial PRIMARY KEY, visit_id bigint REFERENCES visits (id));
    CREATE TABLE track_segments (id bigserial PRIMARY KEY, track_id bigint NOT NULL, start_index integer NOT NULL);
    INSERT INTO visits (user_id, started_at, place_id) VALUES
      (1, '2026-01-05 10:00', 7), (1, '2026-01-05 10:00', 7), (1, '2026-01-05 10:00', 7),
      (1, '2026-01-06 10:00', 7), (1, '2026-01-05 10:00', NULL), (1, '2026-01-05 10:00', NULL);
    INSERT INTO points (visit_id) VALUES (2), (3), (1), (4), (6);
    INSERT INTO track_segments (track_id, start_index) VALUES (1, 0), (1, 0), (1, 5), (2, 0), (1, 5);
    """)

    :ok
  end

  test "20260730210200 over duplicate visits ends with a valid index, one visit per key and the points on the keeper" do
    scratch_sql!("""
    CREATE TABLE place_visits (id bigserial PRIMARY KEY, visit_id bigint NOT NULL REFERENCES visits (id), place_id bigint NOT NULL);
    INSERT INTO place_visits (visit_id, place_id) VALUES (1, 7), (2, 7), (3, 7), (4, 7);
    """)

    assert column_values(
             "SELECT count(*) - count(DISTINCT (user_id, started_at, place_id)) FROM visits WHERE place_id IS NOT NULL"
           ) ==
             [2]

    step("20260730210200").(ScratchRepo)

    assert valid?("idx_visits_user_started_at_place_unique")
    assert column_values("SELECT id FROM visits ORDER BY id") == [1, 4, 5, 6]
    assert column_values("SELECT visit_id FROM points ORDER BY id") == [1, 1, 1, 4, 6]
    assert column_values("SELECT visit_id FROM place_visits ORDER BY id") == [1, 4]
  end

  test "20260730210200 without a place_visits table still collapses the duplicate visits and builds the index" do
    step("20260730210200").(ScratchRepo)

    assert valid?("idx_visits_user_started_at_place_unique")
    assert column_values("SELECT id FROM visits ORDER BY id") == [1, 4, 5, 6]
    assert column_values("SELECT visit_id FROM points ORDER BY id") == [1, 1, 1, 4, 6]
  end

  test "20260730210300 over duplicate segments ends with a valid index and the lowest id per key" do
    assert column_values(
             "SELECT count(*) - count(DISTINCT (track_id, start_index)) FROM track_segments"
           ) ==
             [2]

    step("20260730210300").(ScratchRepo)

    assert valid?("idx_track_segments_track_start_index_unique")
    assert column_values("SELECT id FROM track_segments ORDER BY id") == [1, 3, 4]
  end

  defp step(version) do
    {^version, fun, transaction: false} = List.keyfind(V1_11_0.steps(), version, 0)
    fun
  end

  defp valid?(index) do
    column_values("SELECT indisvalid FROM pg_index WHERE indexrelid = '#{index}'::regclass") ==
      [true]
  end

  defp column_values(sql), do: ScratchRepo.query!(sql, [], log: false).rows |> List.flatten()
end
