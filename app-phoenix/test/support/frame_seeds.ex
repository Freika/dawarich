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

  @tables ~w(users families family_memberships places areas tags visits place_visits notes tracks track_segments points stats taggings active_storage_blobs route_videos active_storage_attachments)

  def load(name), do: "test/fixtures/map_frames/#{name}.json" |> File.read!() |> Jason.decode!()

  def load_family(name),
    do: "test/fixtures/family_pages/#{name}.json" |> File.read!() |> Jason.decode!()

  def seed_management!(name) do
    fixture = "test/fixtures/share_management/#{name}.json" |> File.read!() |> Jason.decode!()

    for actor <- fixture["actors"] do
      {:ok, until, _} = DateTime.from_iso8601(actor["active_until"])
      attrs = Map.new(actor, fn {key, value} -> {String.to_existing_atom(key), value} end)

      RailsUser.insert!(
        Map.merge(attrs, %{
          active_until: DateTime.to_naive(until),
          api_key: "a9fpl-fixture-#{actor["id"]}"
        })
      )
    end

    for row <- fixture["trips"], do: ApiGolden.insert!("trips", row)
    for row <- fixture["before"], do: ApiGolden.insert!("shared_links", row)
    Dawarich.Accounts.get(fixture["actor_id"])
  end

  def seed_family!(%{"actors" => actors, "rows" => rows, "actor_id" => actor_id}) do
    for user <- actors do
      attrs = Map.new(user, fn {key, value} -> {String.to_existing_atom(key), value} end)
      attrs = Map.put(attrs, :active_until, naive(user["active_until"]))
      RailsUser.insert!(Map.put(attrs, :api_key, "a9fpl-fixture-#{user["id"]}"))
    end

    for table <-
          ~w(families family_memberships family_invitations family_location_requests points),
        row <- Map.get(rows, table, []),
        do: ApiGolden.insert!(table, row)

    if actor_id, do: Dawarich.Accounts.get(actor_id)
  end

  def seed!(state, repo \\ Repo)
  def seed!(%{"user" => nil}, _repo), do: nil

  def seed!(%{"user" => u, "rows" => rows}, repo) do
    RailsUser.insert!(user_attrs(u), repo)

    for table <- @tables,
        row <- Map.get(rows, table, []),
        row["id"] != u["id"] or table != "users" do
      row =
        if table == "family_memberships",
          do: Map.update!(row, "role", &Map.get(%{"owner" => 0, "member" => 1}, &1, &1)),
          else: row

      row =
        if table == "active_storage_blobs" and is_map(row["metadata"]),
          do: Map.update!(row, "metadata", &Jason.encode!/1),
          else: row

      if table == "users",
        do: RailsUser.insert!(user_attrs(row), repo),
        else: ApiGolden.insert!(table, row, repo)
    end

    repo.get(Dawarich.Accounts.User, u["id"])
  end

  def seed_place_remainder!(entry) do
    before = entry["before"]
    actor = before["actor"]
    RailsUser.insert!(user_attrs(actor))

    owners =
      Enum.flat_map(~w(places visits notes tags), fn table ->
        Enum.map(before[table], & &1["user_id"])
      end)
      |> Enum.uniq()

    for id <- owners,
        id != nil and id != actor["id"],
        do: RailsUser.insert!(%{id: id, email: "a8-place-#{id}@example.invalid"})

    for table <- ~w(places visits place_visits notes tags taggings), row <- before[table] do
      row =
        case table do
          "places" ->
            Map.update!(
              row,
              "source",
              &Map.get(%{"manual" => 0, "photon" => 1, "gpx_waypoint" => 2}, &1)
            )

          "visits" ->
            Map.update!(
              row,
              "status",
              &Map.get(%{"suggested" => 0, "confirmed" => 1, "declined" => 2}, &1)
            )

          _ ->
            row
        end

      row =
        if table in ~w(places notes) do
          Map.update!(row, "lonlat", fn
            [lon, lat] -> "SRID=4326;POINT(#{lon} #{lat})"
            nil -> nil
          end)
        else
          row
        end

      ApiGolden.insert!(table, row)
    end

    id = hd(before["places"])["id"]

    for table <- ~w(places taggings),
        do:
          Repo.query!("SELECT setval($1::text::regclass, $2, false)", ["#{table}_id_seq", id + 10])

    Dawarich.Accounts.get(actor["id"])
  end

  defp user_attrs(user) do
    Map.new(user, fn {key, value} ->
      value =
        if key in ~w(active_until visits_redetected_at created_at updated_at deleted_at),
          do: naive(value),
          else: value

      {String.to_atom(key), value}
    end)
  end

  defp naive(nil), do: nil

  defp naive(iso),
    do: iso |> NaiveDateTime.from_iso8601!() |> NaiveDateTime.truncate(:microsecond)

  defp stamp, do: NaiveDateTime.utc_now(:second)
end
