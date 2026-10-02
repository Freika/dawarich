defmodule Dawarich.Geocoding.Countries do
  @moduledoc false

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @aliases %{
    "United States" => "United States of America",
    "Serbia" => "Republic of Serbia",
    "Tanzania" => "United Republic of Tanzania",
    "Vatican City" => "Vatican",
    "Palestinian Territory" => "Palestine",
    "Palestinian Territories" => "Palestine",
    "Congo-Brazzaville" => "Republic of the Congo",
    "Eswatini" => "eSwatini",
    "Côte d'Ivoire" => "Ivory Coast",
    "Côte d’Ivoire" => "Ivory Coast",
    "Timor-Leste" => "East Timor",
    "The Gambia" => "Gambia",
    "Cape Verde" => "Cabo Verde",
    "Hong Kong" => "Hong Kong S.A.R.",
    "Macau" => "Macao S.A.R",
    "Macao" => "Macao S.A.R",
    "Congo-Kinshasa" => "Democratic Republic of the Congo",
    "Saint Barthélemy" => "Saint Barthelemy",
    "São Tomé and Príncipe" => "São Tomé and Principe"
  }

  def aliases, do: @aliases

  def find(repo, name, code) do
    code = if Ruby.present?(code), do: String.upcase(code)
    by_name = if Ruby.present?(name), do: first(repo, "name", Map.get(@aliases, name, name))
    by_name = if code && (by_name == nil or by_name.iso_a2 != code), do: nil, else: by_name
    by_name || (code && first(repo, "iso_a2", code))
  end

  defp first(repo, column, value) do
    case repo.query!(
           "SELECT id, iso_a2 FROM countries WHERE #{column} = $1 ORDER BY id LIMIT 1",
           [value],
           log: false
         ).rows do
      [[id, iso_a2]] -> %{id: id, iso_a2: iso_a2}
      [] -> nil
    end
  end
end
