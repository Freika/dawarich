defmodule Dawarich.A10InsightsFixture do
  @moduledoc false
  alias Dawarich.Repo
  @now ~N[2026-06-15 10:00:00]
  def seed do
    corpus =
      Jason.decode!(File.read!(Path.expand("../fixtures/insights/b3-corpus.json", __DIR__)))

    for user <- corpus["users"] do
      Repo.query!(
        "INSERT INTO users(id,email,status,plan,settings,active_until,created_at,updated_at) VALUES($1,$2,1,1,$3,$4,$5,$5)",
        [user["id"], user["email"], user["settings"], timestamp(user["active_until"]), @now],
        log: false
      )
    end

    for stat <- corpus["stats"] do
      Repo.query!(
        "INSERT INTO stats(id,user_id,year,month,distance,flight_distance,toponyms,daily_distance,created_at,updated_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)",
        Enum.map(
          ~w(id user_id year month distance flight_distance toponyms daily_distance),
          &stat[&1]
        ) ++
          [timestamp(stat["created_at"]), timestamp(stat["updated_at"])],
        log: false
      )
    end

    for [id, user, time, country, city, lon, lat] <- corpus["points"] do
      Repo.query!(
        "INSERT INTO points(id,user_id,timestamp,country_name,city,lonlat,created_at,updated_at) VALUES($1,$2,$3,$4,$5,ST_SetSRID(ST_MakePoint($6,$7),4326),$8,$8)",
        [id, user, time, country, city, lon, lat, @now],
        log: false
      )
    end

    for visit <- corpus["visits"] do
      Repo.query!(
        "INSERT INTO visits(id,user_id,name,status,started_at,ended_at,duration,deleted_at,created_at,updated_at) VALUES($1,$2,$3,1,$4,$5,$6,$7,$8,$8)",
        Enum.map(~w(id user_id name), &visit[&1]) ++
          [
            timestamp(visit["started_at"]),
            timestamp(visit["ended_at"]),
            visit["duration"],
            timestamp(visit["deleted_at"]),
            @now
          ],
        log: false
      )
    end

    Enum.find(corpus["users"], &(&1["email"] == "e2e-stats@dawarich.test"))
  end

  defp timestamp(nil), do: nil

  defp timestamp(value) do
    {:ok, time, _} = DateTime.from_iso8601(value)
    DateTime.to_naive(time)
  end
end
