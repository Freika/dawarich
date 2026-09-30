defmodule Dawarich.Test.TripsSeeds do
  @moduledoc false

  alias Dawarich.Repo
  alias Dawarich.Test.RailsUser

  @path """
  UPDATE trips SET path = ST_SetSRID(ST_MakeLine(ARRAY(
    SELECT ST_MakePoint(c.x, c.y) FROM unnest($2::float8[], $3::float8[]) WITH ORDINALITY AS c(x, y, i) ORDER BY c.i
  )), 4326) WHERE id = $1
  """

  @point """
  INSERT INTO points (id, user_id, timestamp, lonlat, tracker_id, source_id, anomaly, created_at, updated_at)
  VALUES ($1, $2, $3, ST_SetSRID(ST_MakePoint($4, $5), 4326)::geography, $6, $7, $8, $9, $9)
  """

  @planned %{
    "planned_days" => %{date: ~D[2026-05-10], position: 1},
    "planned_reservations" => %{title: "Hotel"},
    "planned_accommodations" => %{name: "Pension"},
    "planned_travellers" => %{name: "Ada"},
    "planned_unplanned_places" => %{name: "Museum", position: 1}
  }

  def user!(id, settings \\ %{"timezone" => "Europe/Berlin"}),
    do:
      RailsUser.insert!(%{
        id: id,
        email: "a8-#{id}@dawarich.test",
        settings: settings,
        api_key: "a8-k-#{id}"
      })

  def trip!(attrs) do
    {path, attrs} = Map.pop(attrs, :path)

    row =
      Map.merge(
        %{
          name: "trip #{attrs.id}",
          distance: 1000,
          visited_countries: ["Germany"],
          started_at: ~N[2026-05-09 06:00:00],
          ended_at: ~N[2026-05-12 20:00:00],
          created_at: stamp(),
          updated_at: stamp()
        },
        attrs
      )

    Repo.insert_all("trips", [row])
    if path, do: path!(attrs.id, path)
    attrs.id
  end

  def path!(id, coordinates) do
    {xs, ys} = coordinates |> Enum.map(fn [x, y] -> {x * 1.0, y * 1.0} end) |> Enum.unzip()
    Repo.query!(@path, [id, xs, ys])
  end

  def empty_path!(id),
    do:
      Repo.query!(
        "UPDATE trips SET path = 'SRID=4326;LINESTRING EMPTY'::geometry WHERE id = $1",
        [id]
      )

  def point!(attrs) do
    [lon, lat] = attrs.at

    Repo.query!(@point, [
      attrs.id,
      attrs.user_id,
      attrs.timestamp,
      lon * 1.0,
      lat * 1.0,
      attrs[:tracker_id],
      attrs[:source_id],
      attrs[:anomaly],
      stamp()
    ])
  end

  def source!(id, tracker_id),
    do:
      Repo.insert_all("point_sources", [
        %{
          id: id,
          tracker_id: tracker_id,
          digest: "a8s1#{id}",
          created_at: stamp(),
          updated_at: stamp()
        }
      ])

  def country!(name, a2, a3),
    do:
      Repo.insert_all("countries", [
        %{name: name, iso_a2: a2, iso_a3: a3, created_at: stamp(), updated_at: stamp()}
      ])

  def note!(attrs) do
    Repo.insert_all("notes", [
      %{
        id: attrs.id,
        attachable_type: "Trip",
        attachable_id: attrs.trip_id,
        user_id: attrs.user_id,
        body: attrs.body,
        noted_at: attrs.noted_at,
        created_at: stamp(),
        updated_at: stamp()
      }
    ])
  end

  def shared_link!(attrs) do
    Repo.insert_all("shared_links", [
      %{
        id: Ecto.UUID.dump!(attrs.id),
        name: "Fixture link",
        resource_type: attrs.resource_type,
        resource_id: attrs.trip_id,
        user_id: attrs.user_id,
        revoked_at: attrs[:revoked_at],
        expires_at: attrs[:expires_at],
        settings: %{},
        created_at: stamp(),
        updated_at: stamp()
      }
    ])
  end

  def planned!(table, trip_id),
    do:
      Repo.insert_all(table, [
        Map.merge(@planned[table], %{trip_id: trip_id, created_at: stamp(), updated_at: stamp()})
      ])

  def trip_source!(id, user_id) do
    Repo.insert_all("trip_sources", [
      %{
        id: id,
        user_id: user_id,
        base_url: "https://trek.example",
        provider: "trek",
        created_at: stamp(),
        updated_at: stamp()
      }
    ])
  end

  def rich_text!(trip_id, body) do
    Repo.insert_all("action_text_rich_texts", [
      %{
        name: "description",
        record_type: "Trip",
        record_id: trip_id,
        body: body,
        created_at: stamp(),
        updated_at: stamp()
      }
    ])
  end

  def poster!(attrs),
    do:
      Repo.insert_all("posters", [
        Map.merge(%{settings: %{}, updated_at: attrs.created_at}, attrs)
      ])

  def route_video!(attrs),
    do: Repo.insert_all("route_videos", [Map.merge(%{updated_at: attrs.created_at}, attrs)])

  def load!(seed, now) do
    for u <- seed["users"],
        do:
          RailsUser.insert!(%{
            id: u["id"],
            email: u["email"],
            settings: u["settings"],
            api_key: u["api_key"]
          })

    for c <- seed["countries"], do: country!(c["name"], c["iso_a2"], c["iso_a3"])
    for s <- seed["sources"], do: source!(s["id"], s["tracker_id"])

    for t <- seed["trips"] do
      trip!(%{
        id: t["id"],
        user_id: t["user_id"],
        name: t["name"],
        distance: t["distance"],
        visited_countries: t["visited_countries"],
        started_at: naive(t["started_at"]),
        ended_at: naive(t["ended_at"]),
        last_recalculated_at:
          t["recalculated_offset"] && NaiveDateTime.add(now, -t["recalculated_offset"]),
        path: t["path"]
      })
    end

    for p <- seed["points"] do
      point!(%{
        id: p["id"],
        user_id: p["user_id"],
        timestamp: p["timestamp"],
        at: [p["lon"], p["lat"]],
        tracker_id: p["tracker_id"],
        source_id: p["source_id"],
        anomaly: p["anomaly"]
      })
    end

    for n <- seed["notes"],
        do:
          note!(%{
            id: n["id"],
            trip_id: n["trip_id"],
            user_id: n["user_id"],
            body: n["body"],
            noted_at: naive(n["noted_at"])
          })

    for l <- seed["shared_links"] do
      shared_link!(%{
        id: l["id"],
        resource_type: l["resource_type"],
        trip_id: l["trip_id"],
        user_id: l["user_id"],
        revoked_at: if(l["revoked"], do: NaiveDateTime.add(now, -86_400)),
        expires_at: l["expires_offset"] && NaiveDateTime.add(now, l["expires_offset"])
      })
    end

    for p <- seed["posters"],
        do:
          poster!(%{
            id: p["id"],
            user_id: p["user_id"],
            name: p["name"],
            status: p["status"],
            created_at: naive(p["created_at"])
          })

    for v <- seed["route_videos"] do
      route_video!(%{
        id: v["id"],
        user_id: v["user_id"],
        name: v["name"],
        status: v["status"],
        settings: v["settings"],
        expired_at: naive(v["expired_at"]),
        created_at: naive(v["created_at"])
      })
    end

    :ok
  end

  defp naive(text), do: NaiveDateTime.from_iso8601!(text)
  defp stamp, do: NaiveDateTime.utc_now()
end
