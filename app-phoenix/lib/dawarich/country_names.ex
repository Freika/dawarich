defmodule Dawarich.CountryNames do
  @moduledoc false

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @source Path.expand("../../priv/country_names.json", __DIR__)
  @external_resource @source
  @data @source |> File.read!() |> Jason.decode!()
  @names @data["names"]
  @aliases @data["aliases"]
  @territories @data["territories"]

  @codes_source Path.expand("../../priv/country_codes.json", __DIR__)
  @external_resource @codes_source
  @codes @codes_source |> File.read!() |> Jason.decode!() |> Map.fetch!("countries")

  def iso_codes(name) do
    case code_row(name) do
      [_name, iso2, iso3, _flag] -> {iso2, iso3}
      nil -> {nil, nil}
    end
  end

  def flag(iso2) do
    code = String.upcase(iso2)

    Enum.find_value(@codes, fn [_name, candidate, _iso3, flag] ->
      if candidate == code, do: flag
    end)
  end

  def table(repo \\ Dawarich.Repo),
    do:
      for(
        [name, code] <- repo.query!("SELECT name, iso_a2 FROM countries", []).rows,
        do: {name, code}
      )

  def normalize(name, table) do
    cond do
      Ruby.blank?(name) -> nil
      List.keymember?(table, name, 0) -> name
      true -> standardize(name) || name
    end
  end

  def standardize(name) do
    down = String.downcase(name)

    cond do
      name in @names ->
        name

      Map.has_key?(@aliases, name) ->
        @aliases[name]

      true ->
        Enum.find(@names, &(String.downcase(&1) == down)) ||
          Enum.find(@names, &either_contains?(String.downcase(&1), down))
    end
  end

  def flag_code(name, table) when is_binary(name) do
    down = String.downcase(name)

    code =
      Map.get(Map.new(table), name) ||
        Enum.find_value(table, fn {candidate, code} ->
          candidate = String.downcase(candidate)
          if down == candidate or either_contains?(down, candidate), do: code
        end)

    code |> taiwan() |> territory(name) |> alpha2()
  end

  def flag_code(_name, _table), do: nil

  defp code_row(name) do
    if Ruby.blank?(name) do
      nil
    else
      down = String.downcase(name)

      exact_row(name) || (@aliases[name] && exact_row(@aliases[name])) ||
        Enum.find(@codes, fn [candidate | _] -> String.downcase(candidate) == down end) ||
        Enum.find(@codes, fn [candidate | _] ->
          either_contains?(String.downcase(candidate), down)
        end)
    end
  end

  defp exact_row(name), do: Enum.find(@codes, fn [candidate | _] -> candidate == name end)

  defp either_contains?(a, b), do: String.contains?(a, b) or String.contains?(b, a)

  defp taiwan("CN-TW"), do: "TW"
  defp taiwan(code), do: code

  defp territory("-99", name), do: @territories[name]
  defp territory(code, _name), do: code

  defp alpha2(code) when is_binary(code),
    do: if(code =~ ~r/\A[A-Za-z]{2}\z/, do: String.downcase(code))

  defp alpha2(nil), do: nil
end
