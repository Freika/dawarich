defmodule Dawarich.Maps.Entities do
  @moduledoc false
  alias Dawarich.{Maps, Repo, RubyInteger}
  alias Dawarich.Places.{Nearby, WebDelete, WebWrite}

  @place ~w(name latitude longitude note tag_ids)

  def tags(scope),
    do: Maps.with_actor(scope, &{:ok, Dawarich.TagPages.index(&1)})

  def place(scope, id) do
    Maps.with_actor(scope, fn actor ->
      case Repo.query!(
             "SELECT id,name,latitude::float8,longitude::float8,note,ARRAY(SELECT tag_id FROM taggings WHERE taggable_type='Place' AND taggable_id=places.id ORDER BY tag_id) FROM places WHERE id=$1 AND user_id=$2",
             [RubyInteger.to_i(id), actor.id]
           ).rows do
        [[id, name, lat, lon, note, tags]] ->
          {:ok,
           %{
             "id" => id,
             "name" => name,
             "latitude" => lat,
             "longitude" => lon,
             "note" => note,
             "tag_ids" => tags
           }}

        [] ->
          {:error, :not_found}
      end
    end)
  end

  def save_place(scope, id, attrs, opts \\ []) do
    Maps.with_actor(scope, fn actor ->
      action = if is_nil(id), do: :create, else: :update
      attrs = for key <- @place, Map.has_key?(attrs, key), into: %{}, do: {key, attrs[key]}

      case WebWrite.run(Repo, action, actor, id && RubyInteger.to_i(id), attrs, ctx(scope, opts)) do
        {:ok, %{id: saved}} -> {:ok, saved}
        {:invalid, errors} -> {:error, {:invalid, errors}}
        {:error, :not_found} -> {:error, :not_found}
        _ -> {:error, :unavailable}
      end
    end)
  end

  def delete_place(scope, id, opts \\ []) do
    Maps.with_actor(scope, fn actor ->
      case WebDelete.run(Repo, actor, RubyInteger.to_i(id), ctx(scope, opts)) do
        {:ok, _} -> :ok
        {:error, :not_found} -> {:error, :not_found}
        _ -> {:error, :unavailable}
      end
    end)
  end

  def visit_status(scope, id, status, opts \\ [])
      when status in ~w(confirmed declined suggested) do
    visit(
      scope,
      opts,
      &Dawarich.Visits.WebUpdate.run(Repo, &1, RubyInteger.to_i(id), %{"status" => status}, &2)
    )
  end

  def delete_visit(scope, id, opts \\ []) do
    visit(scope, opts, &Dawarich.Visits.WebDelete.run(Repo, &1, RubyInteger.to_i(id), %{}, &2))
  end

  def nearby(scope, %{"latitude" => lat, "longitude" => lon}, opts \\ []) do
    Maps.with_actor(scope, fn actor ->
      with {lat, _} <- Float.parse(to_string(lat)), {lon, _} <- Float.parse(to_string(lon)) do
        {:ok, Nearby.fetch(actor, lat, lon, Keyword.get(opts, :radius, 0.5), 10, cache: true)}
      else
        _ -> {:error, :invalid}
      end
    end)
  end

  defp visit(scope, opts, command) do
    Maps.with_actor(scope, fn actor ->
      case command.(actor, Map.merge(ctx(scope, opts), %{self_hosted: hosted(opts)})) do
        {:ok, _} -> :ok
        {:error, reason} when is_atom(reason) -> {:error, reason}
        _ -> {:error, :not_found}
      end
    end)
  end

  defp ctx(scope, opts),
    do: %{now: Keyword.get_lazy(opts, :now, &DateTime.utc_now/0), locale: scope.locale || "en"}

  defp hosted(opts),
    do: Keyword.get_lazy(opts, :self_hosted?, &Dawarich.ReleaseMigration.self_hosted?/0)
end
