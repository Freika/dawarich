defmodule Dawarich.TagPages do
  @moduledoc false

  alias Dawarich.Repo

  @columns "t.id, t.name, t.icon, t.color, t.demo, t.privacy_radius_meters"

  def index(user) do
    Repo.query!(
      "SELECT #{@columns}, (SELECT count(*) FROM public.taggings g " <>
        "JOIN public.places p ON p.id = g.taggable_id " <>
        "WHERE g.tag_id = t.id AND g.taggable_type = 'Place') " <>
        "FROM public.tags t WHERE t.user_id = $1 ORDER BY t.name",
      [user.id]
    ).rows
    |> Enum.map(fn [id, name, icon, color, demo, radius, count] ->
      Map.put(row([id, name, icon, color, demo, radius]), :places_count, count)
    end)
  end

  def edit(user, id) do
    case Repo.query!(
           "SELECT #{@columns} FROM public.tags t WHERE t.user_id = $1 AND t.id = $2",
           [user.id, id]
         ).rows do
      [values] -> {:ok, row(values)}
      [] -> :rails
    end
  end

  defp row([id, name, icon, color, demo, radius]),
    do: %{id: id, name: name, icon: icon, color: color, demo: demo, privacy_radius_meters: radius}
end
