defmodule Dawarich.Test.FrameSeeds do
  @moduledoc false

  alias Dawarich.Repo
  alias Dawarich.Test.{ApiGolden, RailsUser}

  @lon 12.3731
  @lat 51.3397

  def user!(id, settings \\ %{"timezone" => "Europe/Berlin"}, attrs \\ %{}) do
    RailsUser.insert!(
      Map.merge(
        %{
          id: id,
          email: "a6s2-#{id}@dawarich.test",
          api_key: "a6s2-k-#{id}",
          settings: settings,
          visits_redetected_at: ~N[2026-09-19 10:00:00]
        },
        attrs
      )
    )

    Dawarich.Accounts.get(id)
  end

  def place!(user_id, id, name, opts \\ []) do
    {dx, dy} = Keyword.get(opts, :offset, {0.0, 0.0})

    lonlat =
      if Keyword.get(opts, :legacy, false),
        do: "NULL",
        else: "ST_SetSRID(ST_MakePoint($7, $6), 4326)::geography"

    Repo.query!(
      "INSERT INTO places (id, user_id, name, city, country, latitude, longitude, lonlat, created_at, updated_at) " <>
        "VALUES ($1, $2, $3, $4, $5, $6::float8, $7::float8, #{lonlat}, now(), now())",
      [id, user_id, name, "Leipzig", "Germany", @lat + dy, @lon + dx]
    )

    id
  end

  def visit!(user_id, id, attrs) do
    row =
      Map.merge(
        %{
          id: id,
          user_id: user_id,
          name: "Visit #{id}",
          status: 1,
          duration: 30,
          created_at: stamp(),
          updated_at: stamp()
        },
        attrs
      )

    Repo.insert_all("visits", [row])
    id
  end

  def track!(user_id, id, attrs) do
    row =
      Map.merge(
        %{
          distance: 1000,
          duration: 600,
          avg_speed: 6.0,
          dominant_mode: 2,
          elevation_gain: nil,
          elevation_loss: nil
        },
        attrs
      )

    Repo.query!(
      "INSERT INTO tracks (id, user_id, start_at, end_at, distance, duration, avg_speed, dominant_mode, " <>
        "elevation_gain, elevation_loss, original_path, created_at, updated_at) " <>
        "VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, ST_GeomFromText($11, 4326), now(), now())",
      [
        id,
        user_id,
        row.start_at,
        row.end_at,
        row.distance,
        row.duration,
        row.avg_speed,
        row.dominant_mode,
        row.elevation_gain,
        row.elevation_loss,
        "LINESTRING(#{@lon} #{@lat}, #{@lon + 0.008} #{@lat + 0.004})"
      ]
    )

    id
  end

  def segment!(track_id, id, attrs),
    do:
      Repo.insert_all("track_segments", [
        Map.merge(%{id: id, track_id: track_id, created_at: stamp(), updated_at: stamp()}, attrs)
      ])

  def tag!(user_id, id, name, place_id, created_at) do
    Repo.insert_all("tags", [
      %{
        id: id,
        user_id: user_id,
        name: name,
        color: "#aa33cc",
        created_at: stamp(),
        updated_at: stamp()
      }
    ])

    Repo.insert_all("taggings", [
      %{
        id: id,
        tag_id: id,
        taggable_type: "Place",
        taggable_id: place_id,
        created_at: created_at,
        updated_at: stamp()
      }
    ])
  end

  def suggest!(id, visit_id, place_id),
    do:
      Repo.insert_all("place_visits", [
        %{
          id: id,
          visit_id: visit_id,
          place_id: place_id,
          created_at: stamp(),
          updated_at: stamp()
        }
      ])

  def point!(user_id, id, timestamp, attrs \\ %{}) do
    Repo.query!(
      "INSERT INTO points (id, user_id, timestamp, visit_id, country_name, lonlat, created_at, updated_at) " <>
        "VALUES ($1, $2, $3, $4, $5, ST_SetSRID(ST_MakePoint($6, $7), 4326)::geography, now(), now())",
      [id, user_id, timestamp, attrs[:visit_id], attrs[:country_name], @lon, @lat]
    )
  end

  def stat!(user_id, year, month),
    do:
      Repo.insert_all("stats", [
        %{
          user_id: user_id,
          year: year,
          month: month,
          distance: 0,
          created_at: stamp(),
          updated_at: stamp()
        }
      ])

  @tables ~w(places areas tags taggings visits place_visits tracks track_segments points stats)

  def load(name), do: "test/fixtures/map_frames/#{name}.json" |> File.read!() |> Jason.decode!()

  def seed!(%{"user" => nil}), do: nil

  def seed!(%{"user" => u, "rows" => rows}) do
    RailsUser.insert!(%{
      id: u["id"],
      email: u["email"],
      theme: u["theme"],
      settings: u["settings"],
      admin: u["admin"],
      status: u["status"],
      plan: u["plan"],
      active_until: naive(u["active_until"]),
      subscription_source: u["subscription_source"],
      changelog_consent: u["changelog_consent"],
      api_key: u["api_key"],
      visits_redetected_at: naive(u["visits_redetected_at"])
    })

    for table <- @tables, row <- Map.get(rows, table, []), do: ApiGolden.insert!(table, row)
    Dawarich.Accounts.get(u["id"])
  end

  defp naive(nil), do: nil

  defp naive(iso),
    do: iso |> NaiveDateTime.from_iso8601!() |> NaiveDateTime.truncate(:microsecond)

  defp stamp, do: NaiveDateTime.utc_now(:second)
end
