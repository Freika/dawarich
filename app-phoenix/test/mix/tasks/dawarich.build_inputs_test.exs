defmodule Mix.Tasks.Dawarich.BuildInputsTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir
  @moduletag timeout: 300_000

  setup %{tmp_dir: tmp} do
    source = Dawarich.Build.root()
    root = Path.join(tmp, "retained")
    out = Path.join(tmp, "out")

    for path <-
          ~w(app/assets app/javascript vendor/assets vendor/javascript config/locales config/achievements config/achievements.yml config/importmap.rb config/shared_link_wordlist.txt lib/assets/admin1_world.geojson lib/assets/countries.geojson.gz app-phoenix/priv) do
      target = Path.join(root, path)
      File.mkdir_p!(Path.dirname(target))
      File.cp_r!(Path.join(source, path), target)
    end

    %{source: source, root: root, out: out}
  end

  @tag :a12f4_a23_1
  test "native build inputs work from retained data without Rails executable source", %{
    source: source,
    root: root,
    out: out
  } do
    for path <-
          ~w(Gemfile Gemfile.lock config/application.rb config/boot.rb app/models app/helpers app/views bin/rails) do
      refute File.exists?(Path.join(root, path))
    end

    previous = Application.fetch_env!(:dawarich, :rails_root)
    Application.put_env(:dawarich, :rails_root, root)

    try do
      assert Dawarich.Build.root() == root
      Mix.Tasks.Dawarich.BuildInputs.run(["--root", Dawarich.Build.root(), "--out", out])
    after
      Application.put_env(:dawarich, :rails_root, previous)
    end

    for {name, expected} <- [
          {"i18n", Dawarich.Build.I18n.export(source)},
          {"achievements",
           Dawarich.Build.Achievements.export(
             source,
             Jason.decode!(IO.iodata_to_binary(Dawarich.Build.I18n.export(source)))
           )}
        ] do
      assert File.read!(Path.join(out, "tmp/phoenix/#{name}.json")) ==
               IO.iodata_to_binary(expected)
    end

    assets = json(out, "config/sprockets-manifest.json")["assets"]

    for logical <- ~w(application.js tailwind.css inter-font.css favicon/favicon.ico) do
      assert File.regular?(Path.join([out, "public/assets", Map.fetch!(assets, logical)]))
    end
  end

  @tag :a12f4_a23_2
  test "native export preserves strict importmap and required runtime geo data", %{
    root: root,
    out: out
  } do
    Mix.Tasks.Dawarich.BuildInputs.run(["--root", root, "--out", out])
    assets = json(out, "config/sprockets-manifest.json")["assets"]
    imports = json(out, "tmp/phoenix/importmap.json")["imports"]
    assert imports["application"] == "/assets/" <> assets["application.js"]

    assert imports["controllers/application"] ==
             "/assets/" <> assets["controllers/application.js"]

    assert json(out, "tmp/phoenix/i18n.json")["en"]["number"]["nth"] == %{}

    for {input, output} <- [
          {"app-phoenix/priv/time_zones.json", "tmp/phoenix/time_zones.json"},
          {"config/shared_link_wordlist.txt", "priv/shared_link_wordlist.txt"},
          {"lib/assets/countries.geojson.gz", "priv/countries.geojson.gz"},
          {"lib/assets/admin1_world.geojson", "priv/admin1_world.geojson"}
        ] do
      assert File.regular?(Path.join(out, output)), output
      assert File.read!(Path.join(out, output)) == File.read!(Path.join(root, input))
    end

    File.write!(Path.join(root, "config/importmap.rb"), "\nKernel.system('false')\n", [:append])

    assert_raise ArgumentError, ~r/unsupported line/, fn ->
      Mix.Tasks.Dawarich.BuildInputs.run(["--root", root, "--out", out])
    end
  end

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
