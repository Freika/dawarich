defmodule Dawarich.Posters.Generation do
  @moduledoc false
  alias Dawarich.{Jobs, RailsRoot, Storage}
  alias Dawarich.Jobs.Processed
  alias Dawarich.Posters.{Geometry, NativeRenderer, Publication, TrackBuilder}
  alias Dawarich.State.Lease
  alias DawarichWeb.Translate

  def run(id, user_id, event, locale, opts \\ []) do
    repo = Keyword.get(opts, :repo, Jobs.repo())

    if Processed.done?(repo, event) do
      :ok
    else
      if repo.query!("SELECT id FROM posters WHERE id=$1 AND user_id=$2", [id, user_id]).rows ==
           [],
         do: raise(Ecto.NoResultsError, queryable: "posters")

      case Lease.with_lease(repo, "posters:#{id}", fn holder ->
             case Publication.prepare(repo, id, user_id, event, holder, locale) do
               {:ok, :skip} -> :ok
               {:ok, ctx} -> generate(repo, ctx, opts)
               {:error, :lost} -> :lost
               {:error, error} -> raise error
             end
           end) do
        {:ok, result} -> result
        {:error, :timeout} -> {:error, :timeout}
      end
    end
  end

  defp generate(repo, ctx, opts) do
    track = TrackBuilder.build(ctx.user_id, ctx.settings, repo)

    cond do
      is_nil(track) ->
        fail(repo, ctx, "no_location_data")

      not Geometry.intersects?(track, ctx.settings) ->
        fail(repo, ctx, "track_outside_area")

      true ->
        case Publication.progress(repo, ctx, "drawing_map") do
          {:ok, _} -> render(repo, ctx, track, opts)
          {:error, :lost} -> :lost
          {:error, error} -> raise error
        end
    end
  rescue
    _error -> fail(repo, ctx, "failed")
  end

  defp render(repo, ctx, track, opts) do
    renderer =
      Keyword.get(opts, :renderer, fn poster, track, locale ->
        NativeRenderer.render(poster, track, locale, Keyword.get(opts, :render_options, []))
      end)

    result = renderer.(ctx, track, ctx.locale)

    storage =
      Keyword.get_lazy(opts, :storage, fn ->
        Storage.config!(System.get_env(), RailsRoot.join(""))
      end)

    dir = Storage.tmp_dir!(storage, "poster-publish-#{ctx.event_id}-#{ctx.holder}")

    try do
      outputs = [{"png", "image/png", result.png}, {"pdf", "application/pdf", result.pdf}]

      upload = fn -> upload!(storage, dir, ctx, outputs) end

      case Publication.publish(repo, ctx, upload, &discard(storage, &1)) do
        {:ok, result} when result in [:published, :duplicate] -> :ok
        {:error, :lost} -> :lost
        {:error, error} -> raise error
      end
    after
      File.rm_rf!(dir)
    end
  end

  defp upload!(storage, dir, ctx, outputs) do
    uploaded =
      Enum.reduce_while(outputs, {:ok, []}, fn {ext, type, bytes}, {:ok, blobs} ->
        key = attachment_key(ctx, ext)

        try do
          filename = "poster_#{ctx.id}.#{ext}"
          path = Path.join(dir, filename)
          File.write!(path, bytes)
          {:cont, {:ok, blobs ++ [Storage.put!(storage, path, filename, type, key)]}}
        rescue
          error ->
            Storage.delete(storage, key)
            {:halt, {:error, error, blobs}}
        end
      end)

    case uploaded do
      {:ok, blobs} ->
        blobs

      {:error, error, blobs} ->
        discard(storage, blobs)
        raise error
    end
  end

  defp attachment_key(ctx, ext) do
    :crypto.hash(:sha256, "#{ctx.id}:#{ctx.event_id}:#{ext}")
    |> Base.encode16(case: :lower)
    |> binary_part(0, 28)
  end

  defp discard(storage, blobs) do
    Enum.each(blobs, &Storage.delete(storage, &1.key))
    :ok
  end

  defp fail(repo, ctx, key) do
    message = Translate.t(ctx.locale, "services.posters.generate." <> key, %{})

    case Publication.fail(repo, ctx, message) do
      {:ok, _} -> :ok
      {:error, :lost} -> :lost
      {:error, error} -> raise error
    end
  end
end
