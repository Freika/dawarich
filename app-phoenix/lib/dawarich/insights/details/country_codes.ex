defmodule Dawarich.Insights.Details.CountryCodes do
  @moduledoc "Rails' Country.names_to_iso_a2: the cached Ruby hash when warm, else the table read like Hash#to_h."
  alias Dawarich.{RailsCache, Repo}
  alias Dawarich.RailsCache.Value

  def load do
    case RailsCache.get("countries_names_to_iso_a2", hash: :ordered) do
      {:ok, %Value{tag: :hash_default, value: {pairs, _default}}} -> pairs
      _ -> to_h(Repo.query!("SELECT name,iso_a2 FROM countries").rows)
    end
  end

  def lookup(country, pairs) do
    case List.keyfind(pairs, country, 0) do
      {_, code} when code not in [nil, false] ->
        code

      _ ->
        country = String.downcase(country)

        Enum.find_value(pairs, fn {name, code} ->
          name = String.downcase(name)

          if country == name or String.contains?(country, name) or
               String.contains?(name, country),
             do: {:found, code}
        end)
        |> case do
          {:found, code} -> code
          nil -> nil
        end
    end
  end

  defp to_h(rows) do
    last = Map.new(rows, fn [name, code] -> {name, code} end)
    rows |> Enum.map(&hd/1) |> Enum.uniq() |> Enum.map(&{&1, last[&1]})
  end
end
