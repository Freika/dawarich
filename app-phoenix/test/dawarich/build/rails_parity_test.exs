defmodule Dawarich.Build.RailsParityTest do
  use ExUnit.Case, async: false

  alias Dawarich.Build
  alias Dawarich.Build.Sprockets.{Compiler, Writer}
  alias Jason.OrderedObject

  @moduletag :rails_parity
  @moduletag timeout: :infinity

  @proc ~r/,"nth":\{"ordinals":"#<Proc:[^"]*","ordinalized":"#<Proc:[^"]*"\}/
  @env [{"RAILS_ENV", "test"}, {"SECRET_KEY_BASE_DUMMY", "1"}, {"LANG", "en_US.UTF-8"}]

  setup_all do
    root = Build.root()
    dir = Path.join(System.tmp_dir!(), "a12g-parity-#{System.unique_integer([:positive])}")
    elixir = Path.join(dir, "elixir")
    assets = Writer.write!(elixir, Compiler.compile(root), Writer.now())
    manifest = Path.join(elixir, "config/sprockets-manifest.json")

    run!(root, "bundle", [
      "exec",
      "rake",
      "phoenix:i18n[#{dir}/i18n.json]",
      "phoenix:achievements[#{dir}/achievements.json]",
      "phoenix:importmap[#{dir}/importmap.json,#{manifest}]",
      "phoenix:assets[#{dir}/ruby,#{dir}/ruby-manifest.json]"
    ])

    on_exit(fn -> File.rm_rf!(dir) end)
    %{root: root, dir: dir, elixir: elixir, assets: assets}
  end

  test "the i18n export is Rails' byte for byte, less the two Active Support lambdas", %{
    root: root,
    dir: dir
  } do
    ruby = File.read!(Path.join(dir, "i18n.json"))

    assert length(Regex.scan(@proc, ruby)) == 1
    assert IO.iodata_to_binary(Build.I18n.export(root)) == Regex.replace(@proc, ruby, "")
  end

  test "the achievements export is Rails' byte for byte", %{root: root, dir: dir} do
    translations = root |> Build.I18n.export() |> IO.iodata_to_binary() |> Jason.decode!()

    assert IO.iodata_to_binary(Build.Achievements.export(root, translations)) ==
             File.read!(Path.join(dir, "achievements.json"))
  end

  test "the importmap export is Rails' byte for byte over the same manifest", %{
    root: root,
    dir: dir,
    assets: assets
  } do
    assert IO.iodata_to_binary(Build.Importmap.export(root, assets)) ==
             File.read!(Path.join(dir, "importmap.json"))
  end

  test "every compiled asset is Rails' byte for byte", %{dir: dir, elixir: elixir} do
    ruby = Path.join(dir, "ruby")
    ours = Path.join(elixir, "public/assets")
    files = relative_files(ruby)

    assert files == relative_files(ours)

    for f <- files do
      a = File.read!(Path.join(ruby, f))
      b = File.read!(Path.join(ours, f))

      if String.ends_with?(f, ".gz") do
        <<a_head::binary-4, _::binary-4, a_rest::binary>> = a
        <<b_head::binary-4, _::binary-4, b_rest::binary>> = b
        assert {b_head, b_rest} == {a_head, a_rest}, f
      else
        assert b == a, f
      end
    end

    assert manifest(Path.join(dir, "ruby-manifest.json")) ==
             manifest(Path.join(elixir, "config/sprockets-manifest.json"))
  end

  test "npm's Tailwind CLI writes the standalone binary's bytes", %{root: root, dir: dir} do
    standalone =
      run!(root, "bundle", [
        "exec",
        "ruby",
        "-e",
        ~s(require "tailwindcss/ruby"; print Tailwindcss::Ruby.executable)
      ])

    args =
      ~w(-i app/assets/stylesheets/application.tailwind.css -c config/tailwind.config.js --minify -o)

    run!(root, standalone, args ++ [Path.join(dir, "standalone.css")])

    run!(
      root,
      Path.join(root, "node_modules/.bin/tailwindcss"),
      args ++ [Path.join(dir, "npm.css")]
    )

    assert File.read!(Path.join(dir, "npm.css")) == File.read!(Path.join(dir, "standalone.css"))
  end

  defp run!(root, command, args) do
    {output, status} =
      System.cmd(command, args,
        cd: root,
        env: [{"BROWSERSLIST_IGNORE_OLD_DATA", "1"} | @env],
        stderr_to_stdout: true
      )

    if status != 0, do: flunk("#{command} #{Enum.join(args, " ")} exited #{status}:\n#{output}")
    output
  end

  defp relative_files(dir) do
    dir
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(&Path.relative_to(&1, dir))
    |> Enum.sort()
  end

  defp manifest(path) do
    raw = File.read!(path)
    decoded = Jason.decode!(raw, objects: :ordered_objects)
    assert Jason.encode!(decoded) == raw, "#{path} is not compact JSON"

    %OrderedObject{values: sections} = decoded

    sections
    |> Enum.map(fn
      {"files", %OrderedObject{values: files}} ->
        {"files", files |> Enum.map(&without_mtime/1) |> Enum.sort_by(&elem(&1, 0))}

      {"assets", %OrderedObject{values: assets}} ->
        {"assets", Enum.sort_by(assets, &elem(&1, 0))}
    end)
    |> Enum.map(fn {name, values} -> {name, %OrderedObject{values: values}} end)
    |> then(&Jason.encode!(%OrderedObject{values: &1}))
  end

  defp without_mtime({name, %OrderedObject{values: fields}}),
    do: {name, %OrderedObject{values: List.keydelete(fields, "mtime", 0)}}
end
