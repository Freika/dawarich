defmodule Dawarich.Build.NativeAssetsTest do
  use ExUnit.Case, async: true
  import Plug.Test

  @moduletag :tmp_dir

  defp build!(dir) do
    assert 0 ==
             Esbuild.install_and_run(:native, [
               "--outdir=#{dir}",
               "--metafile=#{Path.join(dir, "meta.json")}",
               "--log-level=warning"
             ])

    dir
  end

  defp inputs(dir) do
    dir
    |> Path.join("meta.json")
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("inputs")
    |> Map.keys()
  end

  test "the native bundle includes LiveView and no Hotwire module", %{tmp_dir: dir} do
    inputs = dir |> build!() |> inputs()

    assert Enum.any?(inputs, &String.contains?(&1, "phoenix_live_view"))
    refute Enum.any?(inputs, &Regex.match?(~r/@hotwired|stimulus|turbo|rails_bridge/i, &1))
  end

  test "emoji-mart is a separate lazily loaded chunk", %{tmp_dir: dir} do
    build!(dir)
    app = File.read!(Path.join(dir, "app.js"))
    chunks = dir |> Path.join("*.js") |> Path.wildcard()

    refute app =~ "EmojiMart"
    assert length(chunks) > 1
  end

  test "the map-matching demo is a lazily loaded chunk and MapLibre stays an external URL import",
       %{tmp_dir: dir} do
    inputs = dir |> build!() |> inputs()
    app = File.read!(Path.join(dir, "app.js"))
    chunks = for path <- Path.wildcard(Path.join(dir, "*.js")), do: File.read!(path)

    refute app =~ "mttdcBceuqX"
    assert Enum.any?(chunks, &(&1 =~ "mttdcBceuqX"))
    assert app =~ ~s|import("/maplibre/6.4.1/maplibre-gl.mjs")|
    refute Enum.any?(inputs, &String.contains?(&1, "maplibre"))
    refute Enum.any?(inputs, &String.contains?(&1, "app/javascript"))
  end

  test "the demo adds at most 2 KB to the eagerly loaded native bundle", %{tmp_dir: dir} do
    build!(dir)

    outputs =
      dir |> Path.join("meta.json") |> File.read!() |> Jason.decode!() |> Map.fetch!("outputs")

    {app, _} = Enum.find(outputs, fn {path, _} -> Path.basename(path) == "app.js" end)

    demo_bytes =
      for path <- eager(outputs, [app], MapSet.new()),
          {input, %{"bytesInOutput" => bytes}} <- outputs[path]["inputs"],
          String.contains?(input, "demo"),
          reduce: 0,
          do: (sum -> sum + bytes)

    assert demo_bytes in 1..2048
  end

  defp eager(_outputs, [], seen), do: seen

  defp eager(outputs, [path | rest], seen) do
    if MapSet.member?(seen, path) do
      eager(outputs, rest, seen)
    else
      static =
        for %{"kind" => "import-statement", "path" => import} <- outputs[path]["imports"],
            Map.has_key?(outputs, import),
            do: import

      eager(outputs, static ++ rest, MapSet.put(seen, path))
    end
  end

  test "ordinary page never loads map or studio engines", %{tmp_dir: dir} do
    build!(dir)

    outputs =
      Path.join(dir, "meta.json") |> File.read!() |> Jason.decode!() |> Map.fetch!("outputs")

    {app, _} = Enum.find(outputs, fn {path, _} -> Path.basename(path) == "app.js" end)

    eager_inputs =
      for path <- eager(outputs, [app], MapSet.new()),
          {input, _} <- outputs[path]["inputs"],
          do: input

    refute Enum.any?(eager_inputs, &Regex.match?(~r{js/(map/|poster/|video/)}, &1))
    assert Enum.any?(inputs(dir), &String.contains?(&1, "map/runtime/host.js"))
  end

  test "native map chunks contain no Rails controller or Hotwire input", %{tmp_dir: dir} do
    build!(dir)
    graph = inputs(dir)
    assert Enum.any?(graph, &String.contains?(&1, "hooks/map.js"))
    assert Enum.any?(graph, &String.contains?(&1, "map/data/studio_source.js"))

    refute Enum.any?(
             graph,
             &Regex.match?(
               ~r{app/javascript|controllers/|@hotwired|rails_bridge|activestorage},
               &1
             )
           )

    chunks = for path <- Path.wildcard(Path.join(dir, "*.js")), do: File.read!(path)
    assert Enum.any?(chunks, &String.contains?(&1, "/maplibre/6.4.1/maplibre-gl.mjs"))
  end

  test "density libraries stay outside the ordinary map-open graph", %{tmp_dir: dir} do
    build!(dir)

    outputs =
      dir |> Path.join("meta.json") |> File.read!() |> Jason.decode!() |> Map.fetch!("outputs")

    {host, _} =
      Enum.find(outputs, fn {_path, output} ->
        Map.has_key?(output["inputs"], "js/map/runtime/host.js")
      end)

    open_inputs =
      for path <- eager(outputs, [host], MapSet.new()),
          input <- Map.keys(outputs[path]["inputs"]),
          do: input

    refute Enum.any?(
             open_inputs,
             &Regex.match?(
               ~r{h3-js|pmtiles|layers/density|layers/photos|ui/photo_marker|layers/entities|data/entity_geojson},
               &1
             )
           )

    assert Enum.any?(inputs(dir), &String.contains?(&1, "h3-js"))
    assert Enum.any?(inputs(dir), &String.contains?(&1, "pmtiles"))
  end

  test "the vendored MapLibre module and the basemap styles the demo loads ship in the public root" do
    for path <-
          ~w(maplibre/6.4.1/maplibre-gl.mjs maps_maplibre/styles/light.json maps_maplibre/styles/dark.json) do
      assert File.regular?(Dawarich.RailsRoot.join("public/" <> path)), path
    end
  end

  test "the endpoint serves files from the native output directory" do
    native = Application.app_dir(:dawarich, "priv/static/native")
    probe = "probe-#{System.unique_integer([:positive])}.js"
    File.mkdir_p!(native)
    File.write!(Path.join(native, probe), "export {}")
    on_exit(fn -> File.rm(Path.join(native, probe)) end)

    conn = DawarichWeb.Endpoint.call(conn(:get, "/native/" <> probe), [])

    assert conn.status == 200
    assert hd(Plug.Conn.get_resp_header(conn, "content-type")) =~ "javascript"
  end

  test "native_path points at the native output through the endpoint's static paths" do
    assert DawarichWeb.Assets.native_path("app.js") == "/native/app.js"
  end
end
