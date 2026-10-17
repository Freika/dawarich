defmodule Dawarich.Build.Sprockets.WriterTest do
  use ExUnit.Case, async: true

  alias Dawarich.Build.Sprockets.Writer

  @moduletag :tmp_dir

  test "digest paths are Sprockets' etag of version 1.0, inserted before the last extension" do
    assert Writer.digest_path("manifest.js", String.duplicate("\n", 8)) ==
             "manifest-597b5199768f5efff6ec880a4180aec95099b04608cc46e56dfe4e0940ee4665.js"

    assert Writer.digest_path("turbo.min.js.map", "x") =~ ~r/\Aturbo\.min\.js-[0-9a-f]{64}\.map\z/
  end

  test "writes assets, gzip twins and Rails' manifest shape", %{tmp_dir: out} do
    css = "body{}\n"

    results = [
      %{
        logical: "a/b.css",
        source: css,
        digest_path: Writer.digest_path("a/b.css", css),
        gzip: true
      },
      %{
        logical: "logo.png",
        source: <<137, 80>>,
        digest_path: Writer.digest_path("logo.png", <<137, 80>>),
        gzip: false
      }
    ]

    assets = Writer.write!(out, results, "2026-10-02T00:00:00+00:00")
    path = Path.join([out, "public/assets", assets["a/b.css"]])
    gz = File.read!(path <> ".gz")

    assert File.read!(path) == css
    assert :zlib.gunzip(gz) == css
    assert binary_part(gz, 0, 10) == <<0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 2, 3>>
    refute File.exists?(Path.join([out, "public/assets", assets["logo.png"] <> ".gz"]))

    manifest =
      out
      |> Path.join("config/sprockets-manifest.json")
      |> File.read!()
      |> Jason.decode!(objects: :ordered_objects)

    assert Enum.map(manifest.values, &elem(&1, 0)) == ~w(files assets)
    {_, entry} = hd(manifest["files"].values)
    assert Enum.map(entry.values, &elem(&1, 0)) == ~w(logical_path mtime size digest integrity)
    assert entry["integrity"] == "sha256-" <> Base.encode64(:crypto.hash(:sha256, css))
    assert entry["mtime"] == "2026-10-02T00:00:00+00:00"
  end
end
