defmodule Dawarich.Build.CompareBuildInputsTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  @script Path.expand("../../../scripts/compare_build_inputs.sh", __DIR__)
  @zones File.read!(Path.expand("../../../priv/time_zones.json", __DIR__))
  @manifest ~s({"files":{"x-1.js":{"logical_path":"x.js","mtime":"2026-10-02T00:00:00+00:00","size":1}},) <>
              ~s("assets":{"x.js":"x-1.js","y.js":"y-2.js"}})

  defp tree!(root, side, files \\ %{}) do
    dir = Path.join(root, side)

    defaults = %{
      "public/assets/x-1.js" => "x",
      "config/sprockets-manifest.json" => @manifest,
      "tmp/phoenix/i18n.json" => "{}",
      "tmp/phoenix/achievements.json" => "{}",
      "tmp/phoenix/importmap.json" => "{}",
      "tmp/phoenix/time_zones.json" => @zones
    }

    for {path, body} <- Map.merge(defaults, files), body != nil do
      full = Path.join(dir, path)
      File.mkdir_p!(Path.dirname(full))
      File.write!(full, body)
    end

    dir
  end

  defp compare(a, b, path \\ System.get_env("PATH")),
    do: System.cmd("/bin/sh", [@script, a, b], env: [{"PATH", path}], stderr_to_stdout: true)

  defp gz(data, level, mtime) do
    z = :zlib.open()
    :ok = :zlib.deflateInit(z, level, :deflated, -15, 8, :default)
    body = :zlib.deflate(z, data, :finish)
    :ok = :zlib.deflateEnd(z)
    :zlib.close(z)

    IO.iodata_to_binary([
      <<0x1F, 0x8B, 8, 0, mtime::little-32, 2, 3>>,
      body,
      <<:erlang.crc32(data)::little-32, byte_size(data)::little-32>>
    ])
  end

  test "the manifest check fails loudly when jq is missing or fails", %{tmp_dir: root} do
    a = tree!(root, "a")
    b = tree!(root, "b")
    bare = Path.join(root, "bare")
    failing = Path.join(root, "failing")
    File.mkdir_p!(bare)
    File.mkdir_p!(failing)

    for tool <- ~w(mktemp rm find sort diff head tail cmp sed gzip od dd),
        do: File.ln_s!(System.find_executable(tool), Path.join(bare, tool))

    File.write!(Path.join(failing, "jq"), "#!/bin/sh\nexit 5\n")
    File.chmod!(Path.join(failing, "jq"), 0o755)

    assert compare(a, b) == {"", 0}
    assert compare(a, b, bare) == {"jq is required\n", 2}
    assert {_, status} = compare(a, b, failing <> ":" <> System.get_env("PATH"))
    assert status != 0
  end

  test "gzip twins may differ only in their MTIME bytes", %{tmp_dir: root} do
    data = Enum.map_join(1..400, ",", &Integer.to_string(rem(&1 * 7919, 1000)))
    refute gz(data, 1, 0) == gz(data, 9, 0)

    a = tree!(root, "a", %{"public/assets/x-1.js.gz" => gz(data, 9, 1_700_000_000)})
    b = tree!(root, "b", %{"public/assets/x-1.js.gz" => gz(data, 9, 0)})
    c = tree!(root, "c", %{"public/assets/x-1.js.gz" => gz(data, 1, 0)})

    assert compare(a, b) == {"", 0}
    assert {output, 1} = compare(a, c)
    assert output =~ "public/assets/x-1.js.gz"
  end

  test "the manifest may differ only in mtime values and asset key order", %{tmp_dir: root} do
    reordered =
      ~s({"files":{"x-1.js":{"logical_path":"x.js","mtime":"2027-01-01T00:00:00+02:00","size":1}},) <>
        ~s("assets":{"y.js":"y-2.js","x.js":"x-1.js"}})

    fields =
      ~s({"files":{"x-1.js":{"size":1,"logical_path":"x.js","mtime":"2026-10-02T00:00:00+00:00"}},) <>
        ~s("assets":{"x.js":"x-1.js","y.js":"y-2.js"}})

    a = tree!(root, "a")
    manifest = &tree!(root, &1, %{"config/sprockets-manifest.json" => &2})

    assert compare(a, manifest.("b", reordered)) == {"", 0}
    assert {_, 1} = compare(a, manifest.("c", @manifest <> "\n"))
    assert {_, 1} = compare(a, manifest.("d", fields))
  end

  test "the first tree's time zones must be the committed list", %{tmp_dir: root} do
    b = tree!(root, "b")

    assert {output, 1} = compare(tree!(root, "a", %{"tmp/phoenix/time_zones.json" => "{}"}), b)
    assert output =~ "priv/time_zones.json"
    assert {_, 1} = compare(tree!(root, "c", %{"tmp/phoenix/time_zones.json" => nil}), b)
  end

  test "an input missing from both trees fails the comparison", %{tmp_dir: root} do
    a = tree!(root, "a", %{"tmp/phoenix/importmap.json" => nil})
    b = tree!(root, "b", %{"tmp/phoenix/importmap.json" => nil})

    assert {output, status} = compare(a, b)
    assert status != 0
    assert output =~ "importmap.json"
  end
end
