defmodule Dawarich.Build.RailsParityTest do
  use ExUnit.Case, async: false

  alias Dawarich.Build
  alias Jason.OrderedObject

  @moduletag :tmp_dir
  @moduletag timeout: 300_000

  @i18n "593e3da1c7e0affcfd62bd56d12106e9a74ca0928c484f642b2c9d4e9292b595"
  @achievements "e3bac66c27a142a0b8b760a576bfb66154ac509aaff809bd43bcbbd22ddec87d"
  @importmap "ec68ae84ab05091becfa76bbfa1c665a225670441c1883003f03c8fc32e1c617"
  @assets "aba058375919f3a61a48a360f24570bcaf75bf3373a64a627b3bc272c0320d8a"
  @manifest "68777a35018b76fec0792415b4aeae096bf77b5af0642d5e5712740b36f8a8b7"

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
