defmodule Dawarich.Test.MapSeeds do
  @moduledoc false

  alias Dawarich.Repo
  alias Dawarich.Test.RailsUser

  def load(name), do: "test/fixtures/map/#{name}.json" |> File.read!() |> Jason.decode!()

  def seed!(state) do
    u = state["user"]
    stamp = NaiveDateTime.utc_now(:second)

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
      api_key: u["api_key"]
    })

    rows = fn key, fun -> Enum.map(state[key] || [], fun) end

    Repo.insert_all(
      "imports",
      rows.(
        "imports",
        &%{
          id: &1["id"],
          name: &1["name"],
          demo: &1["demo"],
          user_id: u["id"],
          created_at: stamp,
          updated_at: stamp
        }
      )
    )

    for p <- state["points"] || [],
        do:
          Repo.query!(
            "INSERT INTO points (id, user_id, import_id, timestamp, lonlat, created_at, updated_at) " <>
              "VALUES ($1, $2, $3, $4, ST_SetSRID(ST_MakePoint($5, $6), 4326)::geography, now(), now())",
            [p["id"], u["id"], p["import_id"], p["timestamp"], p["lon"], p["lat"]]
          )

    for p <- state["places"] || [],
        do:
          Repo.query!(
            "INSERT INTO places (id, user_id, name, latitude, longitude, lonlat, created_at, updated_at) " <>
              "VALUES ($1, $2, $3, $4::numeric, $5::numeric, CASE WHEN $6::float8 IS NULL THEN NULL " <>
              "ELSE ST_SetSRID(ST_MakePoint($6, $7), 4326)::geography END, now(), now())",
            [
              p["id"],
              u["id"],
              p["name"],
              Decimal.new(p["latitude"]),
              Decimal.new(p["longitude"]),
              p["lon"],
              p["lat"]
            ]
          )

    Repo.insert_all(
      "tags",
      rows.(
        "tags",
        &%{
          id: &1["id"],
          name: &1["name"],
          color: &1["color"],
          icon: &1["icon"],
          user_id: u["id"],
          created_at: stamp,
          updated_at: stamp
        }
      )
    )

    Repo.insert_all(
      "shared_links",
      rows.(
        "shared_links",
        &%{
          name: &1["name"],
          resource_type: &1["resource_type"],
          revoked_at: naive(&1["revoked_at"]),
          expires_at: naive(&1["expires_at"]),
          user_id: u["id"],
          created_at: stamp,
          updated_at: stamp
        }
      )
    )

    Repo.insert_all(
      "posters",
      rows.(
        "posters",
        &%{
          id: &1["id"],
          name: &1["name"],
          status: &1["status"],
          settings: &1["settings"],
          user_id: u["id"],
          created_at: naive(&1["created_at"]),
          updated_at: stamp
        }
      )
    )

    Repo.insert_all(
      "route_videos",
      rows.(
        "route_videos",
        &%{
          id: &1["id"],
          name: &1["name"],
          status: &1["status"],
          settings: &1["settings"],
          expired_at: naive(&1["expired_at"]),
          user_id: u["id"],
          created_at: naive(&1["created_at"]),
          updated_at: naive(&1["updated_at"])
        }
      )
    )

    Repo.insert_all(
      "active_storage_blobs",
      rows.(
        "blobs",
        &%{
          id: &1["id"],
          key: &1["key"],
          filename: &1["filename"],
          byte_size: &1["byte_size"],
          checksum: &1["checksum"],
          service_name: &1["service_name"],
          content_type: &1["content_type"],
          created_at: stamp
        }
      )
    )

    Repo.insert_all(
      "active_storage_attachments",
      rows.(
        "attachments",
        &%{
          name: &1["name"],
          record_type: &1["record_type"],
          record_id: &1["record_id"],
          blob_id: &1["blob_id"],
          created_at: stamp
        }
      )
    )

    Repo.insert_all(
      "instance_settings",
      rows.(
        "instance_settings",
        &%{key: &1["key"], value: &1["value"], created_at: stamp, updated_at: stamp}
      )
    )

    Dawarich.Accounts.get(u["id"])
  end

  def naive(nil), do: nil
  def naive(iso), do: iso |> NaiveDateTime.from_iso8601!() |> NaiveDateTime.truncate(:microsecond)
end
