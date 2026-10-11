defmodule Dawarich.Build.RailsParityTest do
  use ExUnit.Case, async: false

  alias Dawarich.Build
  alias Jason.OrderedObject

  @css "9a19331232c5dbcac6e53c8aff67595bb6b72d2896023b7f43f7f70439746eb2"

  @moduletag :tmp_dir
  @moduletag timeout: 300_000

  @i18n "ff72bd2fbe780a84b37cfd0c5ef6e9fa28c01e3023326295224541f1b1e4bd39"
  @achievements "6709610e637f512e76f7e5e1531f3be92c51e70fbf17564f6c3d609458a78198"
  @importmap "73ee634b5edc6fc7a1f55baa085c6cfa1f603fe445274021abb1618fb0973970"
  @assets "874267bddec6acef1dc95030962ad38361b914c83fd6bb7f475339504c9d01eb"
  @manifest "4c809501f79c28919ee1bc9776bd8229077eaf386811ec33d8a3aedca4908add"

  setup_all do
    root = Build.root()

    dir =
      Path.join(System.tmp_dir!(), "native-build-parity-#{System.unique_integer([:positive])}")

    Mix.Tasks.Dawarich.LegacyBuildInputs.run(["--root", root, "--out", dir])
    on_exit(fn -> File.rm_rf!(dir) end)
    %{root: root, dir: dir}
  end

  test "the locales tree export is Rails' byte for byte, including the empty Active Support nth object",
       %{dir: dir} do
    bytes = File.read!(Path.join(dir, "tmp/phoenix/i18n.json"))
    assert get_in(Jason.decode!(bytes), ["en", "number", "nth"]) == %{}
    assert sha(bytes) == @i18n
  end

  test "the achievements export is Rails' byte for byte", %{dir: dir} do
    assert sha(File.read!(Path.join(dir, "tmp/phoenix/achievements.json"))) == @achievements
  end

  test "the importmap export is Rails' byte for byte over the same manifest", %{dir: dir} do
    assert sha(File.read!(Path.join(dir, "tmp/phoenix/importmap.json"))) == @importmap
  end

  test "every compiled asset is Rails' byte for byte", %{dir: dir} do
    base = Path.join(dir, "public/assets")

    bytes =
      for file <- relative_files(base) do
        raw = File.read!(Path.join(base, file))

        normalized =
          if String.ends_with?(file, ".gz") do
            <<head::binary-4, _mtime::binary-4, rest::binary>> = raw
            [head, <<0, 0, 0, 0>>, rest]
          else
            raw
          end

        [file, <<0>>, normalized]
      end

    assert sha(bytes) == @assets
    assert sha(manifest(Path.join(dir, "config/sprockets-manifest.json"))) == @manifest
  end

  test "npm Tailwind retains source classes and deterministic native CSS bytes", %{
    root: root,
    tmp_dir: tmp
  } do
    target = Path.join(tmp, "tailwind.css")

    {output, status} =
      System.cmd(
        Path.join(root, "node_modules/.bin/tailwindcss"),
        [
          "-i",
          "app/assets/stylesheets/application.tailwind.css",
          "-c",
          "config/tailwind.config.js",
          "--minify",
          "-o",
          target
        ],
        cd: root,
        env: [{"BROWSERSLIST_IGNORE_OLD_DATA", "1"}],
        stderr_to_stdout: true
      )

    assert status == 0, output
    bytes = File.read!(target)
    assert sha(bytes) == @css
    assert bytes =~ ~S(.bg-secondary\/10{background-color:)
    assert bytes =~ ~S(.min-w-0{min-width:0})
    repeated = Path.join(tmp, "tailwind-repeated.css")

    {_, repeated_status} =
      System.cmd(
        Path.join(root, "node_modules/.bin/tailwindcss"),
        [
          "-i",
          "app/assets/stylesheets/application.tailwind.css",
          "-c",
          "config/tailwind.config.js",
          "--minify",
          "-o",
          repeated
        ],
        cd: root,
        env: [{"BROWSERSLIST_IGNORE_OLD_DATA", "1"}],
        stderr_to_stdout: true
      )

    assert repeated_status == 0
    assert File.read!(repeated) == bytes
  end

  defp sha(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

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
    %OrderedObject{values: sections} = decoded = Jason.decode!(raw, objects: :ordered_objects)
    assert Jason.encode!(decoded) == raw

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
