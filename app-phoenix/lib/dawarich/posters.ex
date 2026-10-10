defmodule Dawarich.Posters do
  @moduledoc false
  alias Dawarich.{MapGallery, Maps, RubyInteger}
  alias Dawarich.Posters.Persistence

  @recipe ~w(name title lat lon distance theme start_at end_at source route_fill route_opacity route_width)
  @card_settings ~w(progress_phase error)
  @max_id 9_223_372_036_854_775_807

  def gallery(scope),
    do:
      Maps.with_actor(scope, fn user -> {:ok, Enum.map(MapGallery.posters(user.id), &card/1)} end)

  def card(scope, id) do
    with {:ok, id} <- poster_id(id),
         do: Maps.with_actor(scope, fn user -> fetch(user, id) end)
  end

  def create(scope, recipe) when is_map(recipe) and map_size(recipe) > 0 do
    Maps.with_actor(scope, fn user ->
      case Persistence.create(Map.take(recipe, @recipe), user, scope.locale) do
        {:ok, id} -> fetch(user, id)
        {:error, _} -> {:error, :unavailable}
      end
    end)
  end

  def create(_scope, _recipe), do: {:error, :invalid}

  def delete(scope, id) do
    with {:ok, id} <- poster_id(id) do
      Maps.with_actor(scope, fn user ->
        case Persistence.delete(id, user) do
          {:ok, ^id} -> {:ok, id}
          {:error, :missing} -> {:error, :not_found}
        end
      end)
    end
  end

  defp fetch(user, id) do
    case MapGallery.poster(user.id, id) do
      nil -> {:error, :not_found}
      poster -> {:ok, card(poster)}
    end
  end

  defp card(poster), do: Map.update!(poster, :settings, &Map.take(&1 || %{}, @card_settings))

  defp poster_id(id) when is_integer(id) and id > 0 and id <= @max_id, do: {:ok, id}

  defp poster_id(id) when is_binary(id) do
    case RubyInteger.to_i(id) do
      value when value > 0 and value <= @max_id -> {:ok, value}
      _ -> {:error, :not_found}
    end
  end

  defp poster_id(_), do: {:error, :not_found}
end
