defmodule Dawarich.CountryNames do
  @moduledoc false

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @source Path.expand("../../priv/country_names.json", __DIR__)
  @external_resource @source
  @data @source |> File.read!() |> Jason.decode!()
  @names @data["names"]
  @aliases @data["aliases"]
  @territories @data["territories"]

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

  defp either_contains?(a, b), do: String.contains?(a, b) or String.contains?(b, a)

  defp taiwan("CN-TW"), do: "TW"
  defp taiwan(code), do: code

  defp territory("-99", name), do: @territories[name]
  defp territory(code, _name), do: code

  defp alpha2(code) when is_binary(code),
    do: if(code =~ ~r/\A[A-Za-z]{2}\z/, do: String.downcase(code))

  defp alpha2(nil), do: nil
end
