defmodule Dawarich.UserData.Export.Stats do
  @moduledoc false
  alias Dawarich.UserData.Export.Monthly

  def write(repo, user, dir, context),
    do:
      Monthly.write(repo, user, "stats", dir, context, [], Monthly.calendar_month(), fn _id,
                                                                                        pairs ->
        pairs
      end)

  def toponyms(value) do
    entries = if is_list(value), do: List.flatten(value), else: []

    for %Jason.OrderedObject{values: pairs} <- entries,
        is_nil(List.keyfind(pairs, "country", 0, {"country", nil}) |> elem(1)) or
          is_binary(List.keyfind(pairs, "country", 0, {"country", nil}) |> elem(1)) do
      cities = pairs |> List.keyfind("cities", 0, {"cities", nil}) |> elem(1)
      sanitized = sanitize_cities(cities)
      %Jason.OrderedObject{values: List.keystore(pairs, "cities", 0, {"cities", sanitized})}
    end
  end

  defp sanitize_cities(cities) do
    for %Jason.OrderedObject{values: pairs} = city <- if(is_list(cities), do: cities, else: []),
        value = List.keyfind(pairs, "city", 0, {"city", nil}) |> elem(1),
        is_binary(value) and Dawarich.ReleaseMigrations.Effects.Support.Ruby.present?(value),
        do: city
  end
end
