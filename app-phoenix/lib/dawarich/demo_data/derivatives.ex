defmodule Dawarich.DemoData.Derivatives do
  @moduledoc false
  alias Dawarich.DemoData.Importer

  @berlin [
    %{
      "country" => "Germany",
      "cities" => [%{"city" => "Berlin", "points" => 1200, "stayed_for" => 28800}]
    }
  ]
  @prague [
    %{
      "country" => "Germany",
      "cities" => [%{"city" => "Berlin", "points" => 900, "stayed_for" => 21600}]
    },
    %{
      "country" => "Czech Republic",
      "cities" => [%{"city" => "Prague", "points" => 300, "stayed_for" => 2880}]
    }
  ]

  def seed(repo, user, anchor, fixture) do
    tags =
      Map.new(fixture["tags"] || [], fn row ->
        [[id]] =
          repo.query!(
            "INSERT INTO tags (user_id,name,icon,color,demo,created_at,updated_at) VALUES ($1,$2,$3,$4,true,now(),now()) ON CONFLICT(user_id,name) DO UPDATE SET name=tags.name RETURNING id",
            [user.id, row["name"], row["icon"], row["color"]],
            log: false
          ).rows

        {row["key"], id}
      end)

    places =
      Map.new(fixture["places"] || [], fn row ->
        existing =
          repo.query!(
            "SELECT id FROM places WHERE user_id=$1 AND latitude=$2::float8 AND longitude=$3::float8 AND demo=true",
            [user.id, row["lat"], row["lon"]],
            log: false
          ).rows

        id =
          case existing do
            [[id]] ->
              id

            [] ->
              [[id]] =
                repo.query!(
                  "INSERT INTO places (user_id,name,latitude,longitude,lonlat,note,geodata,source,demo,created_at,updated_at) VALUES ($1,$2,$3::float8,$4::float8,ST_SetSRID(ST_MakePoint($4::float8,$3::float8),4326),$5,$6,1,true,now(),now()) RETURNING id",
                  [
                    user.id,
                    row["name"],
                    row["lat"],
                    row["lon"],
                    row["note"],
                    row["geodata"] || %{}
                  ],
                  log: false
                ).rows

              id
          end

        repo.query!(
          "UPDATE places SET name=$2,note=$3,geodata=$4,source=1,updated_at=now() WHERE id=$1",
          [id, row["name"], row["note"], row["geodata"] || %{}],
          log: false
        )

        for key <- row["tags"] || [] do
          repo.query!(
            "INSERT INTO taggings(tag_id,taggable_id,taggable_type,created_at,updated_at) VALUES ($1,$2,'Place',now(),now()) ON CONFLICT DO NOTHING",
            [Map.fetch!(tags, key), id],
            log: false
          )
        end

        {row["key"], id}
      end)

    for row <- fixture["visits"] || [] do
      place = Map.fetch!(places, row["place_key"])
      [[name]] = repo.query!("SELECT name FROM places WHERE id=$1", [place], log: false).rows

      [[id]] =
        repo.query!(
          "INSERT INTO visits(user_id,place_id,name,started_at,ended_at,duration,status,demo,created_at,updated_at) VALUES ($1,$2,$3,to_timestamp($4::bigint) AT TIME ZONE 'UTC',to_timestamp($5::bigint) AT TIME ZONE 'UTC',$6,$7,true,now(),now()) RETURNING id",
          [
            user.id,
            place,
            row["name"] || name,
            anchor + row["starts_offset_seconds"],
            anchor + row["ends_offset_seconds"],
            div(row["ends_offset_seconds"] - row["starts_offset_seconds"], 60),
            Map.fetch!(%{"suggested" => 0, "confirmed" => 1, "declined" => 2}, row["status"])
          ],
          log: false
        ).rows

      for key <- row["alternates"] || [] do
        repo.query!(
          "INSERT INTO place_visits(visit_id,place_id,created_at,updated_at) VALUES ($1,$2,now(),now()) ON CONFLICT DO NOTHING",
          [id, Map.fetch!(places, key)],
          log: false
        )
      end
    end

    trip(repo, user.id, anchor, fixture["trip"])
    stats(repo, user, anchor, fixture["stats_daily"] || [])
  end

  defp trip(_repo, _user, _anchor, nil), do: :ok

  defp trip(repo, user, anchor, row) do
    [[id]] =
      repo.query!(
        "INSERT INTO trips(user_id,name,started_at,ended_at,distance,demo,created_at,updated_at) VALUES ($1,$2,to_timestamp($3::bigint) AT TIME ZONE 'UTC',to_timestamp($4::bigint) AT TIME ZONE 'UTC',$5,true,now(),now()) RETURNING id",
        [
          user,
          row["name"],
          anchor + row["starts_offset_seconds"],
          anchor + row["ends_offset_seconds"],
          row["distance_meters"]
        ],
        log: false
      ).rows

    if row["notes"] not in [nil, ""] do
      body = row["notes"] |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

      repo.query!(
        "INSERT INTO action_text_rich_texts(name,body,record_type,record_id,created_at,updated_at) VALUES ('description',$1,'Trip',$2,now(),now())",
        [body, id],
        log: false
      )
    end
  end

  defp stats(repo, user, anchor, rows) do
    [[date]] =
      repo.query!(
        "SELECT (to_timestamp($1::bigint) AT TIME ZONE $2)::date",
        [anchor, Importer.zone(user)],
        log: false
      ).rows

    rows
    |> Enum.group_by(fn row ->
      day = Date.add(date, row["day_offset"])
      {day.year, day.month}
    end)
    |> Enum.each(fn {{year, month}, days} ->
      daily =
        Enum.map(days, fn row ->
          [Date.add(date, row["day_offset"]).day, row["distance_meters"]]
        end)
        |> Enum.sort()

      toponyms = if Enum.any?(days, & &1["in_prague"]), do: @prague, else: @berlin

      repo.query!(
        "INSERT INTO stats(user_id,year,month,distance,daily_distance,toponyms,created_at,updated_at) VALUES ($1,$2,$3,$4,$5,$6,now(),now()) ON CONFLICT(user_id,year,month) DO NOTHING",
        [user.id, year, month, Enum.sum(Enum.map(daily, &List.last/1)), daily, toponyms],
        log: false
      )
    end)
  end
end
