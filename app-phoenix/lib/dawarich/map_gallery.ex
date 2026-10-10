defmodule Dawarich.MapGallery do
  @moduledoc false

  import Ecto.Query

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.Repo

  def poster(user_id, id) do
    from(p in "posters",
      where: p.user_id == ^user_id and p.id == ^id,
      select: %{id: p.id, name: p.name, status: p.status, settings: p.settings}
    )
    |> Repo.all()
    |> attach("Poster", ["image", "print_pdf"])
    |> List.first()
  end

  def posters(user_id) do
    from(p in "posters",
      where: p.user_id == ^user_id,
      order_by: [desc: p.created_at],
      limit: 10,
      select: %{id: p.id, name: p.name, status: p.status, settings: p.settings}
    )
    |> Repo.all()
    |> Enum.map(&Map.update!(&1, :settings, fn s -> Map.take(s, ["progress_phase", "error"]) end))
    |> attach("Poster", ["image", "print_pdf"])
  end

  def route_videos(user_id, zone) do
    from(v in "route_videos",
      where: v.user_id == ^user_id,
      order_by: [desc: v.created_at, desc: v.id],
      limit: 10,
      select: %{
        id: v.id,
        name: v.name,
        status: v.status,
        settings_json: fragment("?::text", v.settings),
        shown_at:
          fragment(
            "to_char((coalesce(?, ?) AT TIME ZONE 'UTC') AT TIME ZONE ?, 'YYYY-MM-DD\"T\"HH24:MI:SS')",
            v.expired_at,
            v.updated_at,
            ^zone
          )
      }
    )
    |> Repo.all()
    |> Enum.map(
      &%{
        &1
        | settings_json: Ruby.json_text(&1.settings_json),
          shown_at: NaiveDateTime.from_iso8601!(&1.shown_at)
      }
    )
    |> attach("RouteVideo", ["file"])
  end

  def route_video(user_id, id, zone, repo \\ Repo) do
    from(v in "route_videos",
      where: v.user_id == ^user_id and v.id == ^id,
      select: %{
        id: v.id,
        name: v.name,
        status: v.status,
        settings_json: fragment("?::text", v.settings),
        shown_at:
          fragment(
            "to_char((coalesce(?, ?) AT TIME ZONE 'UTC') AT TIME ZONE ?, 'YYYY-MM-DD\"T\"HH24:MI:SS')",
            v.expired_at,
            v.updated_at,
            ^zone
          )
      }
    )
    |> repo.all()
    |> Enum.map(
      &%{
        &1
        | settings_json: Ruby.json_text(&1.settings_json),
          shown_at: NaiveDateTime.from_iso8601!(&1.shown_at)
      }
    )
    |> attach("RouteVideo", ["file"], repo)
    |> List.first()
  end

  def blob_path(blob, disposition \\ nil, secret \\ Dawarich.RailsSecret.fetch()),
    do:
      DawarichWeb.BlobPath.redirect_path(blob.id, blob.filename,
        disposition: disposition,
        secret: secret
      )

  defp attach(rows, type, names, repo \\ Repo)

  defp attach([], _type, _names, _repo), do: []

  defp attach(rows, type, names, repo) do
    ids = Enum.map(rows, & &1.id)

    files =
      from(a in "active_storage_attachments",
        join: b in "active_storage_blobs",
        on: b.id == a.blob_id,
        where: a.record_type == ^type and a.record_id in ^ids and a.name in ^names,
        select: {a.record_id, a.name, %{id: b.id, filename: b.filename}}
      )
      |> repo.all()
      |> Map.new(fn {record, name, blob} -> {{record, name}, blob} end)

    for row <- rows, do: Map.put(row, :files, Map.new(names, &{&1, files[{row.id, &1}]}))
  end
end
