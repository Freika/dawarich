defmodule Dawarich.StatsFixtures do
  @moduledoc false

  alias Dawarich.ScratchRepo

  @path Path.expand("../fixtures/a12d1a/stats.json", __DIR__)
  @tables ~w(countries users imports points flights stats)
  @stamp "2026-10-01T00:00:00"

  def reset! do
    Dawarich.FixtureCleanup.delete!(
      ScratchRepo,
      ~w(countries points stats flights imports notifications)
    )

    :ok
  end

  def case!(id) do
    @path
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("cases")
    |> Enum.find(&(&1["id"] == id)) || raise(ArgumentError, "no stats corpus case #{id}")
  end

  def load!(%{"input" => input} = kase) do
    for table <- @tables, row <- Map.get(input, table, []), do: row!(table, row)

    case kase["generated_points"] do
      %{"sql" => sql, "params" => params} ->
        query(sql, params)

        Dawarich.Test.SeedIds.advance!(
          ScratchRepo,
          "points",
          List.flatten(query("SELECT max(id) FROM points"))
        )

      nil ->
        :ok
    end

    :ok
  end

  def stat(user_id, year, month) do
    case query(
           "SELECT row_to_json(x)::text FROM (SELECT year, month, distance, daily_distance, flight_distance, toponyms, h3_hex_ids, calculation_version, updated_at FROM stats WHERE user_id = $1 AND year = $2 AND month = $3) x",
           [user_id, year, month]
         ) do
      [[json]] -> Jason.decode!(json)
      [] -> nil
    end
  end

  def swept_at(user_id) do
    [[json]] =
      query(
        "SELECT row_to_json(x)::text FROM (SELECT stats_swept_at FROM users WHERE id = $1) x",
        [
          user_id
        ]
      )

    Jason.decode!(json)["stats_swept_at"]
  end

  def calculations do
    for [payload] <-
          query(
            "SELECT payload FROM phoenix.rails_commands WHERE kind = 'stats.calculate_month' ORDER BY id"
          ),
        do: Map.delete(payload, "source_job_id")
  end

  def row!(table, row) do
    columns = row |> Map.keys() |> Enum.sort() |> Enum.map_join(", ", &~s("#{&1}"))

    query(
      "INSERT INTO #{table} (#{columns}) SELECT #{columns} FROM json_populate_record(NULL::#{table}, $1::text::json)",
      [Jason.encode!(row)]
    )

    Dawarich.Test.SeedIds.advance!(ScratchRepo, table, [row["id"]])
    :ok
  end

  def user!(id, settings, extra \\ %{}),
    do:
      row!(
        "users",
        Map.merge(
          %{
            "id" => id,
            "email" => "a12d1a-#{id}@example.invalid",
            "encrypted_password" => "",
            "settings" => settings,
            "status" => 1,
            "created_at" => @stamp,
            "updated_at" => @stamp
          },
          extra
        )
      )

  def point!(id, user_id, timestamp, extra \\ %{}),
    do:
      row!(
        "points",
        Map.merge(
          %{
            "id" => id,
            "user_id" => user_id,
            "timestamp" => timestamp,
            "lonlat" => "SRID=4326;POINT(12.3731 51.3397)",
            "velocity" => "0",
            "anomaly" => false,
            "created_at" => @stamp,
            "updated_at" => @stamp
          },
          extra
        )
      )

  def stat!(id, user_id, year, month, extra \\ %{}),
    do:
      row!(
        "stats",
        Map.merge(
          %{
            "id" => id,
            "user_id" => user_id,
            "year" => year,
            "month" => month,
            "distance" => 0,
            "toponyms" => [],
            "created_at" => @stamp,
            "updated_at" => @stamp
          },
          extra
        )
      )

  def ts(year, month, day, hour \\ 0, minute \\ 0),
    do:
      DateTime.new!(Date.new!(year, month, day), Time.new!(hour, minute, 0)) |> DateTime.to_unix()

  defp query(sql, params \\ []), do: ScratchRepo.query!(sql, params, log: false).rows
end
