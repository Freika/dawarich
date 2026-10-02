defmodule Dawarich.Insights.Details.CountryCodes do
  @moduledoc false
  alias Dawarich.{Repo, RailsCache.Ordered}
  @key "countries_names_to_iso_a2"
  def load(opts \\ []) do
    cache = opts[:cache] || []

    case Ordered.get(@key, cache) do
      {:ok, pairs} ->
        pairs

      _ ->
        repo = opts[:repo] || Repo

        pairs =
          for [name, code] <- repo.query!("SELECT name,iso_a2 FROM countries").rows,
              do: {name, code}

        Ordered.put(@key, pairs, cache ++ [expires_in: 86400])
        pairs
    end
  end

  def lookup(country, pairs) do
    case List.keyfind(pairs, country, 0) do
      {_, code} when code not in [nil, false] ->
        code

      _ ->
        Enum.find_value(pairs, fn {name, code} ->
          country = String.downcase(country)
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
end
