defmodule Dawarich.UsersTest do
  use Dawarich.ScratchCase, async: true, group: :scratch_db

  alias Dawarich.Users

  setup do
    scratch_sql!("""
    CREATE TABLE users (
      id bigserial PRIMARY KEY, status integer DEFAULT 0, deleted_at timestamp(6),
      points_count integer NOT NULL DEFAULT 0, updated_at timestamp(6) NOT NULL);
    CREATE TABLE points (id bigserial PRIMARY KEY, user_id bigint);
    """)

    :ok
  end

  test "corrects a drifted count and leaves updated_at alone" do
    user(1, 10, points: 3)

    assert Users.correct_points_counts(ScratchRepo, 0, 1000) == :done
    assert users() == [{1, 3, ~N[2026-09-01 00:00:00.000000]}]
  end

  test "writes nothing when the count already matches" do
    user(1, 2, points: 2)
    before = xmin(1)

    assert Users.correct_points_counts(ScratchRepo, 0, 1000) == :done
    assert xmin(1) == before
  end

  test "counts active and trial users only" do
    for status <- [0, 1, 2, 3, nil], do: user(status, 9, points: 1)

    Users.correct_points_counts(ScratchRepo, 0, 1000)

    assert Enum.map(users(), &elem(&1, 1)) == [9, 1, 1, 9, 9]
  end

  test "skips soft-deleted users" do
    user(1, 9, points: 1, deleted_at: "2026-09-01 00:00:00")

    Users.correct_points_counts(ScratchRepo, 0, 1000)

    assert Enum.map(users(), &elem(&1, 1)) == [9]
  end

  test "sets zero for a user without points" do
    user(2, 5, points: 0)

    Users.correct_points_counts(ScratchRepo, 0, 1000)

    assert Enum.map(users(), &elem(&1, 1)) == [0]
  end

  test "pages by id: the last id of a full page, then :done after a short one" do
    for _ <- 1..3, do: user(1, 9, points: 1)

    assert Users.correct_points_counts(ScratchRepo, 0, 2) == {:next, 2}
    assert Enum.map(users(), &elem(&1, 1)) == [1, 1, 9]
    assert Users.correct_points_counts(ScratchRepo, 2, 2) == :done
    assert Enum.map(users(), &elem(&1, 1)) == [1, 1, 1]
  end

  defp user(status, stored, opts) do
    deleted_at = if at = opts[:deleted_at], do: "'#{at}'", else: "NULL"

    %{rows: [[id]]} =
      ScratchRepo.query!(
        "INSERT INTO users (status, deleted_at, points_count, updated_at) " <>
          "VALUES (#{status || "NULL"}, #{deleted_at}, #{stored}, '2026-09-01 00:00:00') RETURNING id",
        [],
        log: false
      )

    if opts[:points] > 0 do
      scratch_sql!(
        "INSERT INTO points (user_id) SELECT #{id} FROM generate_series(1, #{opts[:points]})"
      )
    end

    id
  end

  defp users do
    ScratchRepo.query!("SELECT id, points_count, updated_at FROM users ORDER BY id", [],
      log: false
    ).rows
    |> Enum.map(&List.to_tuple/1)
  end

  defp xmin(id) do
    %{rows: [[value]]} =
      ScratchRepo.query!("SELECT xmin::text FROM users WHERE id = $1", [id], log: false)

    value
  end
end
