defmodule Mix.Tasks.Dawarich.BuildInputsTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir
  @moduletag timeout: 300_000

  defp json(out, path), do: out |> Path.join(path) |> File.read!() |> Jason.decode!()

  test "writes every input Phoenix reads from the repository, without Ruby", %{tmp_dir: out} do
    Mix.Tasks.Dawarich.BuildInputs.run(["--root", Dawarich.Build.root(), "--out", out])
    assets = json(out, "config/sprockets-manifest.json")["assets"]

    for logical <-
          ~w(tailwind.css application.css inter-font.css application.js turbo.min.js favicon/favicon.ico) do
      assert File.regular?(Path.join([out, "public/assets", Map.fetch!(assets, logical)])),
             logical
    end

    imports = json(out, "tmp/phoenix/importmap.json")["imports"]
    assert imports["application"] == "/assets/" <> assets["application.js"]
    assert imports["@hotwired/turbo-rails"] == "/assets/" <> assets["turbo.min.js"]

    i18n =
      out
      |> Path.join("tmp/phoenix/i18n.json")
      |> File.read!()
      |> Jason.decode!(objects: :ordered_objects)

    assert Enum.map(i18n.values, &elem(&1, 0)) == ~w(en de es fr pl ca zh)

    definitions = json(out, "tmp/phoenix/achievements.json")["definitions"]
    locales = Enum.sort(~w(en de es fr pl ca zh))

    assert length(definitions) > 200

    assert Enum.all?(definitions, fn definition ->
             is_binary(definition["key"]) and Enum.sort(Map.keys(definition["names"])) == locales
           end)
  end
end
