defmodule Dawarich.Digests.Toponyms do
  @moduledoc false

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.RubyInteger

  defmodule InvalidInteger do
    defexception [:message]
  end

  def sanitize(raw) when is_list(raw) do
    raw
    |> List.flatten()
    |> Enum.filter(&(is_map(&1) and (is_nil(&1["country"]) or is_binary(&1["country"]))))
    |> Enum.map(&Map.put(&1, "cities", valid_cities(&1["cities"])))
  end

  def sanitize(_raw), do: []

  def countries(stats, require_cities \\ true) do
    stats
    |> entries()
    |> Enum.filter(&(Ruby.present?(&1["country"]) and (not require_cities or &1["cities"] != [])))
    |> Enum.map(& &1["country"])
    |> Enum.uniq()
  end

  def cities(stats) do
    stats
    |> entries()
    |> Enum.flat_map(& &1["cities"])
    |> Enum.map(& &1["city"])
    |> Enum.uniq()
  end

  def first_visits(history, year, month \\ nil) do
    current =
      Enum.filter(history, &(&1["year"] == year and (is_nil(month) or &1["month"] == month)))

    previous =
      Enum.filter(
        history,
        &(&1["year"] < year or (month != nil and &1["year"] == year and &1["month"] < month))
      )

    %{
      "countries" => Enum.sort(countries(current) -- countries(previous)),
      "cities" => Enum.sort(cities(current) -- cities(previous))
    }
  end

  def aggregate(stats) do
    stats
    |> entries()
    |> Enum.filter(&(Ruby.present?(&1["country"]) and &1["cities"] != []))
    |> Enum.reduce([], fn top, pairs ->
      add(pairs, top["country"], Enum.map(top["cities"], & &1["city"]), &Enum.uniq(&1 ++ &2))
    end)
    |> Enum.sort_by(fn {_, names} -> -length(names) end)
    |> Enum.map(fn {country, names} ->
      %{"country" => country, "cities" => Enum.map(Enum.sort(names), &%{"city" => &1})}
    end)
  end

  def city_minutes(stats) do
    stats
    |> entries()
    |> Enum.flat_map(& &1["cities"])
    |> Enum.reduce([], fn city, pairs ->
      add(pairs, city["city"], integer!(city["stayed_for"]), &(&1 + &2))
    end)
    |> ranked()
  end

  def ranked(pairs) do
    pairs
    |> Enum.sort_by(fn {_, minutes} -> -minutes end)
    |> Enum.take(10)
    |> Enum.map(fn {name, minutes} -> %{"name" => name, "minutes" => minutes} end)
  end

  def add(pairs, name, value, combine \\ &(&1 + &2)) do
    case Enum.find_index(pairs, fn {key, _} -> key == name end) do
      nil -> pairs ++ [{name, value}]
      index -> List.update_at(pairs, index, fn {key, old} -> {key, combine.(old, value)} end)
    end
  end

  defp entries(stats), do: Enum.flat_map(stats, &sanitize(&1["toponyms"]))

  defp valid_cities(raw) when is_list(raw),
    do: Enum.filter(raw, &(is_map(&1) and is_binary(&1["city"]) and Ruby.present?(&1["city"])))

  defp valid_cities(_raw), do: []

  defp integer!(value) when is_nil(value) or is_number(value) or is_binary(value),
    do: RubyInteger.to_i(value)

  defp integer!(value) do
    type =
      cond do
        is_map(value) -> "Hash"
        is_list(value) -> "Array"
        value == true -> "TrueClass"
        value == false -> "FalseClass"
      end

    raise InvalidInteger, message: "undefined method 'to_i' for an instance of #{type}"
  end
end
