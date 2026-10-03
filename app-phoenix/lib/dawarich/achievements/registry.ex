defmodule Dawarich.Achievements.Registry do
  @moduledoc false

  def all, do: data().definitions
  def find(key), do: Map.get(data().by_key, key)
  def announcer(code), do: Map.get(data().announcers, code)

  def approximations(locale) do
    %{"default" => default, "rules" => rules} = data().transliteration
    Map.merge(default, Map.get(rules, locale, %{}))
  end

  def visible_geography?(code) do
    if Regex.match?(~r/\A[A-Z]{2}\z/, code),
      do: Map.has_key?(data().by_key, "country_" <> String.downcase(code)),
      else: Map.has_key?(data().subdivision_parents, code)
  end

  defp data do
    case :persistent_term.get(__MODULE__, nil) do
      nil -> tap(load(), &:persistent_term.put(__MODULE__, &1))
      data -> data
    end
  end

  defp load do
    path =
      Application.get_env(
        :dawarich,
        :achievements_path,
        Path.join(File.cwd!(), "tmp/phoenix/achievements.json")
      )

    export =
      case File.read(path) do
        {:ok, json} ->
          Jason.decode!(json)

        {:error, reason} ->
          raise "cannot read #{path} (#{reason}); run mix dawarich.achievements"
      end

    definitions = export |> Map.fetch!("definitions") |> Enum.map(&definition/1)

    gridded = Enum.filter(definitions, &(&1.kind == "country" and &1.level == "subdivision"))
    continents = Enum.filter(definitions, &(&1.kind == "continent"))

    %{
      definitions: definitions,
      by_key: Map.new(definitions, &{&1.key, &1}),
      announcers: first_wins(gridded ++ continents),
      subdivision_parents: first_wins(Enum.filter(definitions, &(&1.level == "subdivision"))),
      transliteration: Map.fetch!(export, "transliteration")
    }
  end

  defp first_wins(definitions) do
    Enum.reduce(definitions, %{}, fn definition, index ->
      Enum.reduce(definition.region_codes, index, &Map.put_new(&2, &1, definition))
    end)
  end

  defp definition(map) do
    %{
      key: map["key"],
      kind: map["kind"],
      level: map["level"],
      flat: map["flat"],
      threshold: map["threshold"],
      total: map["total"],
      target: map["target"],
      regions: map["regions"],
      region_codes: map["region_codes"],
      names: map["names"],
      name: map["name"],
      country: map["country"],
      continent: map["continent"],
      parent_key: map["parent_key"],
      card: map["card"]
    }
  end
end
