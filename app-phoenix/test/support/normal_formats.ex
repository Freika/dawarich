defmodule Dawarich.Test.NormalFormats do
  @moduledoc false
  @dir Path.expand("../fixtures/imports/formats", __DIR__)
  @stamp ~N[2026-01-15 23:30:00]
  @sources ~w(google_semantic_history owntracks google_records google_phone_takeout gpx immich_api geojson photoprism_api user_data_archive kml csv tcx fit polarsteps google_photos mobile_photo_library)

  def seed!(name, repo) do
    expected = @dir |> Path.join(name <> ".json") |> File.read!() |> Jason.decode!()
    identities = expected["identities"] || %{}

    {1, [%{id: user}]} =
      repo.insert_all(
        "users",
        [
          %{
            email: "normal-#{System.unique_integer([:positive])}@dawarich.test",
            settings: %{"timezone" => expected["zone"], "locale" => expected["locale"]},
            created_at: @stamp,
            updated_at: @stamp
          }
          |> identity(:id, identities["user_id"])
        ],
        returning: [:id]
      )

    {1, [%{id: id}]} =
      repo.insert_all(
        "imports",
        [
          %{
            user_id: user,
            name: name,
            source: Enum.find_index(@sources, &(&1 == expected["import"]["source"])),
            created_at: @stamp,
            updated_at: @stamp
          }
          |> identity(:id, identities["import_id"])
        ],
        returning: [:id]
      )

    %{
      import: %{id: id, user_id: user},
      path: Path.join(@dir, expected["input"]),
      expected: decode(expected),
      context: %{
        repo: repo,
        zone: expected["zone"],
        locale: expected["locale"],
        now: @stamp,
        altitude_decimal?: true,
        fence: fn fun -> fun.() end
      }
    }
  end

  def decode(%{"__float__" => name}),
    do: %{"Infinity" => :infinity, "-Infinity" => :neg_infinity, "NaN" => :nan}[name]

  def decode(%{"__bytes__" => hex}), do: Base.decode16!(hex, case: :mixed)

  def decode(%{"__symbol_pairs__" => pairs}),
    do:
      Dawarich.Imports.NormalCast.symbolic_hash(Enum.map(pairs, fn [k, v] -> {k, decode(v)} end))

  def decode(%{"__symbol_hash__" => map}),
    do: Dawarich.Imports.NormalCast.symbolic_hash(Enum.map(map, fn {k, v} -> {k, decode(v)} end))

  def decode(map) when is_map(map), do: Map.new(map, fn {key, value} -> {key, decode(value)} end)
  def decode(list) when is_list(list), do: Enum.map(list, &decode/1)
  def decode(value), do: value

  defp identity(attrs, _, nil), do: attrs
  defp identity(attrs, key, value), do: Map.put(attrs, key, value)
end
