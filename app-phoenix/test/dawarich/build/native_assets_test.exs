defmodule Dawarich.Build.NativeAssetsTest do
  use ExUnit.Case, async: true
  import Plug.Test

  @moduletag :tmp_dir

  defp build!(dir, extra \\ []) do
    assert 0 ==
             Esbuild.install_and_run(
               :native,
               [
                 "--outdir=#{dir}",
                 "--metafile=#{Path.join(dir, "meta.json")}",
                 "--log-level=warning"
               ] ++ extra
             )

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

  test "both native studio hooks register without eagerly loading their engines", %{tmp_dir: dir} do
    build!(dir)

    outputs =
      Path.join(dir, "meta.json") |> File.read!() |> Jason.decode!() |> Map.fetch!("outputs")

    {app, _} = Enum.find(outputs, fn {path, _} -> Path.basename(path) == "app.js" end)

    eager_inputs =
      for path <- eager(outputs, [app], MapSet.new()),
          input <- Map.keys(outputs[path]["inputs"]),
          do: input

    for studio <- ~w(poster video) do
      assert Enum.any?(eager_inputs, &String.ends_with?(&1, "hooks/#{studio}_studio.js"))
    end

    refute Enum.any?(eager_inputs, &Regex.match?(~r{js/(poster|video)/|fflate|mp4-muxer}, &1))
  end

  test "both studio engines ship as recursive lazy chunks outside the eager graph", %{
    tmp_dir: dir
  } do
    build!(dir)

    outputs =
      Path.join(dir, "meta.json") |> File.read!() |> Jason.decode!() |> Map.fetch!("outputs")

    {app, _} = Enum.find(outputs, fn {path, _} -> Path.basename(path) == "app.js" end)
    app_graph = eager(outputs, [app], MapSet.new())

    for input <- ~w(js/poster/runtime.js js/video/studio.js) do
      {chunk, _} = Enum.find(outputs, fn {_, output} -> Map.has_key?(output["inputs"], input) end)
      refute MapSet.member?(app_graph, chunk)

      bytes =
        Enum.sum(for path <- eager(outputs, [chunk], MapSet.new()), do: outputs[path]["bytes"])

      assert bytes > 0
    end
  end

  test "production closures measure actual emitted bytes and keep export codecs lazy", %{
    tmp_dir: dir
  } do
    build!(dir, ["--minify"])

    outputs =
      Path.join(dir, "meta.json") |> File.read!() |> Jason.decode!() |> Map.fetch!("outputs")

    chunks =
      Map.new(outputs, fn {path, output} ->
        data = File.read!(Path.join(dir, Path.basename(path)))
        assert byte_size(data) == output["bytes"]
        refute data =~ "// js/"
        {path, %{raw: byte_size(data), gzip: byte_size(:zlib.gzip(data))}}
      end)

    entry = fn input ->
      {path, _} = Enum.find(outputs, fn {_, output} -> Map.has_key?(output["inputs"], input) end)
      path
    end

    roots = %{
      app:
        Enum.find_value(outputs, fn {path, _} -> if Path.basename(path) == "app.js", do: path end),
      map: entry.("js/map/runtime/host.js"),
      poster: entry.("js/poster/runtime.js"),
      video: entry.("js/video/studio.js")
    }

    assert length(Enum.uniq(Map.values(roots))) == 4

    closure_inputs = fn root ->
      for path <- eager(outputs, [root], MapSet.new()),
          input <- Map.keys(outputs[path]["inputs"]),
          do: input
    end

    refute Enum.any?(
             closure_inputs.(roots.app),
             &Regex.match?(~r{js/(map|poster|video)/|h3-js|fflate|mp4-muxer}, &1)
           )

    refute Enum.any?(
             closure_inputs.(roots.map),
             &Regex.match?(~r{js/poster/(runtime|export)|js/video/|h3-js|fflate|mp4-muxer}, &1)
           )

    refute Enum.any?(closure_inputs.(roots.poster), &String.contains?(&1, "mp4-muxer"))
    refute Enum.any?(closure_inputs.(roots.video), &String.contains?(&1, "fflate"))
    graph = inputs(dir)
    assert Enum.any?(graph, &String.contains?(&1, "fflate"))
    assert Enum.any?(graph, &String.contains?(&1, "mp4-muxer"))

    sizes =
      Map.new(roots, fn {name, root} ->
        files = eager(outputs, [root], MapSet.new())

        {name,
         %{
           raw: Enum.sum(for path <- files, do: chunks[path].raw),
           gzip: Enum.sum(for path <- files, do: chunks[path].gzip),
           chunks: MapSet.size(files)
         }}
      end)

    IO.puts("NATIVE_BUILD_BYTES " <> Jason.encode!(sizes))
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
    refute_unapproved_rails_inputs(inputs)
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
               ~r{controllers/|@hotwired|rails_bridge|activestorage},
               &1
             )
           )

    refute_unapproved_rails_inputs(graph)
    chunks = for path <- Path.wildcard(Path.join(dir, "*.js")), do: File.read!(path)
    assert Enum.any?(chunks, &String.contains?(&1, "/maplibre/6.4.1/maplibre-gl.mjs"))
  end

  test "native style and studio dependencies contain no Rails JavaScript inputs", %{
    tmp_dir: dir
  } do
    graph = dir |> build!() |> inputs()
    shared = Enum.filter(graph, &String.contains?(&1, "app/javascript"))
    assert shared == []
  end

  defp approved_style_inputs, do: []

  defp refute_unapproved_rails_inputs(graph) do
    assert Enum.filter(graph, &String.contains?(&1, "app/javascript")) -- approved_style_inputs() ==
             []
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

  test "production static map workers styles poster fonts and RTL assets resolve with their MIME types",
       %{tmp_dir: dir} do
    source_root = Dawarich.RailsRoot.root()
    root = Path.join(dir, "packaged")
    public = Path.join(root, "public")
    File.mkdir_p!(public)

    for directory <- ~w(maplibre maps_maplibre poster_themes) do
      File.cp_r!(Path.join(source_root, "public/" <> directory), Path.join(public, directory))
    end

    font_paths =
      for family <- DawarichWeb.PosterFonts.families(),
          weight <- ~w(400 700),
          do: "poster/#{family}-#{weight}.woff2"

    Dawarich.Build.Sprockets.Writer.write!(
      root,
      Dawarich.Build.Sprockets.Compiler.compile(
        source_root,
        font_paths ++ ["mapbox-gl-rtl-text.js"]
      ),
      Dawarich.Build.Sprockets.Writer.now()
    )

    paths =
      for name <- ~w(maplibre-gl.mjs maplibre-gl-shared.mjs maplibre-gl-worker.mjs),
          do: {"/maplibre/6.4.1/" <> name, "text/javascript"}

    paths =
      paths ++
        [
          {"/maps_maplibre/styles/light.json", "application/json"},
          {"/maps_maplibre/styles/dark.json", "application/json"}
        ] ++
        Enum.map(font_paths, &{DawarichWeb.Assets.stylesheet_path(root, &1), "font/woff2"}) ++
        [{DawarichWeb.Assets.stylesheet_path(root, "mapbox-gl-rtl-text.js"), "text/javascript"}]

    for {path, type} <- paths do
      response =
        conn(:get, path)
        |> then(&%{&1 | req_headers: [{"host", "www.example.com"}]})
        |> DawarichWeb.PublicFiles.call(
          root: public,
          env: %{"RAILS_ENV" => "production", "APPLICATION_HOSTS" => "www.example.com"}
        )

      assert response.status == 200, path
      assert Plug.Conn.get_resp_header(response, "content-type") == [type]
      assert response.halted
      assert File.stat!(Path.join(public, path)).size > 0
    end

    for file <- ~w(maplibre-gl.mjs maplibre-gl-worker.mjs) do
      source = File.read!(Path.join(public, "maplibre/6.4.1/" <> file))
      assert source =~ "./maplibre-gl-shared.mjs"
    end

    style = File.read!(Path.join(public, "maps_maplibre/styles/light.json")) |> Jason.decode!()
    assert URI.parse(style["glyphs"]).scheme == "https"
    assert URI.parse(style["sprite"]).scheme == "https"
  end

  test "native_path points at the native output through the endpoint's static paths" do
    assert DawarichWeb.Assets.native_path("app.js") == "/native/app.js"
  end
end
