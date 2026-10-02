defmodule Dawarich.Wave6Fixtures do
  @moduledoc false

  alias Dawarich.ScratchRepo

  @dir Path.expand("../fixtures/wave6", __DIR__)
  @leipzig {:point, 12.3731, 51.3397}

  def load!(name), do: @dir |> Path.join("#{name}.json") |> File.read!() |> Jason.decode!()

  def reset! do
    ScratchRepo.query!("TRUNCATE places, place_visits, countries RESTART IDENTITY CASCADE", [],
      log: false
    )

    :ok
  end

  def user!(columns \\ %{}) do
    now = NaiveDateTime.utc_now()

    defaults = %{
      "email" => "wave6-#{System.unique_integer([:positive, :monotonic])}@example.test",
      "status" => 1,
      "points_count" => 0,
      "settings" => %{},
      "created_at" => now,
      "updated_at" => now
    }

    insert!("users", Map.merge(defaults, columns))
  end

  def point!(user_id, columns \\ %{}) do
    now = NaiveDateTime.utc_now()

    defaults = %{
      "user_id" => user_id,
      "timestamp" => 1_577_836_800 + System.unique_integer([:positive, :monotonic]),
      "lonlat" => @leipzig,
      "raw_data" => %{},
      "motion_data" => %{},
      "created_at" => now,
      "updated_at" => now
    }

    insert!("points", Map.merge(defaults, columns))
  end

  def track!(user_id, columns \\ %{}) do
    now = NaiveDateTime.utc_now()
    minutes = System.unique_integer([:positive, :monotonic])
    start_at = NaiveDateTime.add(~N[2020-01-01 00:00:00], minutes, :minute)

    defaults = %{
      "user_id" => user_id,
      "start_at" => start_at,
      "end_at" => NaiveDateTime.add(start_at, 30, :minute),
      "original_path" => {:geometry, "LINESTRING(12.3731 51.3397, 12.3831 51.3497)"},
      "created_at" => now,
      "updated_at" => now
    }

    insert!("tracks", Map.merge(defaults, columns))
  end

  def segment!(track_id, columns \\ %{}) do
    now = NaiveDateTime.utc_now()

    insert!(
      "track_segments",
      Map.merge(%{"track_id" => track_id, "created_at" => now, "updated_at" => now}, columns)
    )
  end

  def insert!(table, columns) do
    {names, values} = Enum.unzip(columns)

    {placeholders, params} =
      Enum.map_reduce(values, [], fn
        {:point, lon, lat}, acc ->
          n = length(acc)
          {"ST_SetSRID(ST_MakePoint($#{n + 1}, $#{n + 2}), 4326)::geography", acc ++ [lon, lat]}

        {:geometry, wkt}, acc ->
          {"ST_GeomFromText($#{length(acc) + 1}, 4326)", acc ++ [wkt]}

        value, acc ->
          {"$#{length(acc) + 1}", acc ++ [value]}
      end)

    %{rows: [[id]]} =
      ScratchRepo.query!(
        "INSERT INTO #{table} (#{Enum.join(names, ", ")}) VALUES (#{Enum.join(placeholders, ", ")}) RETURNING id",
        params,
        log: false
      )

    id
  end

  def await_waiter!(pattern) do
    deadline = System.monotonic_time(:millisecond) + 5_000

    if Task.await(Task.async(fn -> poll_waiter(pattern, deadline) end), :infinity) == :timeout,
      do: ExUnit.Assertions.flunk("nothing waited on a row lock in #{pattern}")

    :ok
  end

  defp poll_waiter(pattern, deadline) do
    waiting =
      ScratchRepo.query!(
        """
        SELECT count(DISTINCT l.pid) FROM pg_locks l JOIN pg_stat_activity a ON a.pid = l.pid
        WHERE NOT l.granted AND a.datname = current_database() AND a.query LIKE $1
        """,
        [pattern],
        log: false
      ).rows

    cond do
      waiting == [[1]] ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        :timeout

      true ->
        :erlang.yield()
        poll_waiter(pattern, deadline)
    end
  end

  def local_storage! do
    root = Path.join(System.tmp_dir!(), "wave6-storage-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf(root) end)
    %{service: "local", root: root}
  end
end
