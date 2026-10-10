defmodule Dawarich.TripCorpusTest do
  use ExUnit.Case, async: true

  alias Dawarich.{TimeZoneName, TripDays, TripStream}
  alias Dawarich.Test.TripsSeeds
  alias DawarichWeb.{NumberFormat, TripFormat}

  @dir "test/fixtures/trips"

  defp json(name), do: @dir |> Path.join(name) |> File.read!() |> Jason.decode!()

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
  end

  test "primary windows' JSON and day statistics equal Rails' for every fixture trip" do
    TripsSeeds.load!(json("seed.json"), NaiveDateTime.utc_now())

    for c <- json("windows.json")["trips"] do
      days = TripDays.day_data(c["user_id"], c["from"], c["to"], c["gap"], c["iana"])
      assert days.windows_json == c["windows_json"], inspect(c["trip_id"])
      stats = Enum.sort_by(days.stats, &elem(&1, 0), Date)
      assert length(stats) == length(c["stats"]), inspect(c["trip_id"])

      for {{day, s}, expected} <- Enum.zip(stats, c["stats"]) do
        assert Date.to_iso8601(day) == expected["day"], inspect(c["trip_id"])
        assert NaiveDateTime.to_iso8601(s.first) == expected["first"], inspect(c["trip_id"])
        assert NaiveDateTime.to_iso8601(s.last) == expected["last"], inspect(c["trip_id"])
        assert Float.round(s.distance_m, 6) == expected["distance_m"], inspect(c["trip_id"])
      end
    end
  end

  test "trip_duration equals Rails' in four zones, a Berlin fall-back overlap included" do
    for c <- json("format.json")["durations"] do
      zone = TimeZoneName.to_iana(c["zone"])

      span =
        TripDays.local_span(
          NaiveDateTime.from_iso8601!(c["started_at"]),
          NaiveDateTime.from_iso8601!(c["ended_at"]),
          zone
        )

      {parts, _borrowed} =
        TripDays.duration_parts(span.started_local, span.ended_local, span.previous_month_days)

      assert TripFormat.duration("en", parts) == c["text"], inspect(c)
    end
  end

  test "number_with_precision(…, precision: 1) equals Rails'" do
    for %{"value" => value, "text" => text} <- json("format.json")["precision"],
        do: assert(NumberFormat.with_precision_one("en", value * 1.0) == text, inspect(value))
  end

  test "trip stream names equal Turbo's signed_stream_name" do
    corpus = json("streams.json")

    for %{"trip_id" => id, "signed" => signed} <- corpus["trips"],
        do: assert(TripStream.stream_name(id, corpus["secret"]) == signed)
  end
end
