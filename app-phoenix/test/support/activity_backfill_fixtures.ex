defmodule Dawarich.Test.ActivityBackfillFixtures do
  @moduledoc false
  import ExUnit.Assertions
  alias Dawarich.ScratchRepo

  @dir Path.expand("../fixtures/a12rel", __DIR__)
  @stamp ~N[2026-01-15 23:30:00]

  def corpus, do: @dir |> Path.join("imports.json") |> File.read!() |> Jason.decode!()
  def profile(name), do: Enum.find(corpus()["cases"], &(&1["id"] == name))
  def input(profile), do: File.read!(Path.join(@dir, profile["input"]))

  def seed!(profile) do
    cleanup()

    ScratchRepo.insert_all("users", [
      %{
        id: 987_001,
        email: "a12rel-replay@example.invalid",
        created_at: @stamp,
        updated_at: @stamp
      }
    ])

    for import <- profile["before"]["imports"], do: insert!("imports", import)

    for point <- profile["before"]["points"] do
      insert!("points", point |> Map.put("lonlat", point["ewkb"]) |> Map.delete("ewkb"))
    end
  end

  def cleanup do
    query("DROP TRIGGER IF EXISTS a12rel_activity_failure ON points")
    query("DROP FUNCTION IF EXISTS a12rel_activity_failure()")
    query("DELETE FROM points WHERE user_id=987001")
    query("DELETE FROM imports WHERE user_id=987001")
    query("DELETE FROM users WHERE id=987001")
  end

  def context, do: %{repo: ScratchRepo, zone: corpus()["ambient_zone"], now: @stamp}

  def snapshot do
    query("SELECT to_jsonb(p) FROM points p WHERE user_id=987001 ORDER BY id")
    |> Enum.map(&hd/1)
  end

  def assert_points(expected) do
    assert Enum.map(snapshot(), &Map.take(&1, ["id", "motion_data"])) ==
             Enum.map(expected["points"], &Map.take(&1, ["id", "motion_data"]))
  end

  def assert_untouched(before) do
    assert Enum.map(snapshot(), &Map.delete(&1, "motion_data")) ==
             Enum.map(before, &Map.delete(&1, "motion_data"))
  end

  def committed_snapshot do
    ScratchRepo.checkout(fn ->
      [[first]] = query("SELECT pg_backend_pid()")

      {second, data} =
        Task.async(fn ->
          ScratchRepo.checkout(fn ->
            [[pid]] = query("SELECT pg_backend_pid()")
            {pid, snapshot()}
          end)
        end)
        |> Task.await()

      assert first != second
      data
    end)
  end

  def query(sql, params \\ []), do: ScratchRepo.query!(sql, params, log: false).rows

  defp insert!(table, attrs) do
    query("INSERT INTO #{table} SELECT (json_populate_record(NULL::#{table},$1::json)).*", [
      attrs
    ])
  end
end
