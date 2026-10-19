defmodule Dawarich.Build.NativeAssetsTest do
  use ExUnit.Case, async: true
  import Plug.Test

  @moduletag :tmp_dir

  @http_chrome_cap 2 * 1024
  @places_cap 2 * 1024
  @m6_inputs ~w(js/map/hooks/map_state.js js/map/hooks/map.js js/map/hooks/family.js js/map/hooks/map_preview.js js/onboarding/hook.js js/poster/hook.js js/map/hooks/public_map.js js/map/hooks/trip.js js/video/hook.js js/onboarding/dialog.js)
  @other_slack 1024
  @chrome_inputs ~w(js/analytics_events.js js/hooks/achievement_unlocks.js js/hooks/changelog_widget.js)
  @chrome_base_bytes 6_707 + 548
  @places_inputs ~w(js/hooks/place_draft.js js/hooks/ordinary_dialog.js)
  @m5_inputs ~w(js/charts/hook.js js/charts/heatmap.js js/editor/hook.js js/insights/year_map_hook.js)
  @other_base_bytes 335_463 - 16_713 - 1_844 - 1_632 - 232 + 22 + 31 + 389
  @m4_inputs [
    {~w(js/hooks/archive_checksum.js js/uploaders/direct.js), 8416},
    {~w(js/hooks/credential_qr.js js/hooks/credential_value.js), 4256},
    {~w(js/hooks/family_confirm.js js/hooks/family_invitation_clipboard.js), 2918},
    {~w(js/hooks/sharing_controls.js js/hooks/clipboard.js), 6365},
    {~w(js/map/shared/lazy_maps.js js/map/shared/shared_erase.js js/hooks/index.js), 3748}
  ]

  @tag trix_pin: true
  test "native editor builds pinned Trix with no ActionText transport", %{tmp_dir: dir} do
    manifest = File.read!("assets/package.json") |> Jason.decode!()
    assert manifest["dependencies"]["trix"] == "2.1.19"
    graph = dir |> build!() |> inputs()
    assert Enum.any?(graph, &String.contains?(&1, "node_modules/trix/"))
    refute Enum.any?(graph, &Regex.match?(~r/@rails|actiontext|activestorage/i, &1))
  end

  defp engine_inputs(inputs),
    do: inputs -- (@m6_inputs ++ Enum.flat_map(@m4_inputs, &elem(&1, 0)))

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

  test "HTTP auth eager graph fits 20 KiB without a socket or legacy runtime", %{tmp_dir: dir} do
    build!(dir)

    outputs =
      dir |> Path.join("meta.json") |> File.read!() |> Jason.decode!() |> Map.fetch!("outputs")

    entry = Enum.find(outputs, fn {path, _} -> Path.basename(path) == "auth_http.js" end)
    assert entry != nil
    {path, _} = entry
    graph = eager(outputs, [path], MapSet.new())
    assert Enum.sum(Enum.map(graph, &outputs[&1]["bytes"])) <= 20 * 1024
    inputs = Enum.flat_map(graph, &Map.keys(outputs[&1]["inputs"]))

    refute Enum.any?(
             inputs,
             &Regex.match?(
               ~r/phoenix_live_view|phoenix\/|@hotwired|stimulus|turbo|maplibre|chartkick|trix|rails_bridge/i,
               &1
             )
           )
  end

  test "HTTP chrome adds at most 2 KiB to the native eager graph", %{tmp_dir: dir} do
    bytes = dir |> build!() |> app_input_bytes() |> Map.take(@chrome_inputs) |> Map.values()
    assert Enum.sum(bytes) - @chrome_base_bytes <= @http_chrome_cap
  end

  test "native eager graph outside the milestone inputs stays within 1 KiB of base", %{
    tmp_dir: dir
  } do
    inputs = dir |> build!() |> app_input_bytes()
    assert Map.fetch!(inputs, "js/insights/year_map_hook.js") <= 2 * 1024
    refute Map.has_key?(inputs, "js/insights/year_map.js")

    bytes =
      inputs
      |> Map.drop(
        @chrome_inputs ++
          @places_inputs ++ @m5_inputs ++ @m6_inputs ++ Enum.flat_map(@m4_inputs, &elem(&1, 0))
      )

    assert Enum.sum(Map.values(bytes)) <= @other_base_bytes + @other_slack
  end

  test "M6 hooks retain an independent eager byte cap", %{tmp_dir: dir} do
    bytes = dir |> build!() |> app_input_bytes() |> Map.take(@m6_inputs) |> Map.values()
    assert Enum.sum(bytes) <= 14 * 1024 + 512
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
      assert Enum.any?(eager_inputs, &String.ends_with?(&1, "#{studio}/hook.js"))
    end

    refute Enum.any?(
             engine_inputs(eager_inputs),
             &Regex.match?(~r{js/(poster|video)/|fflate|mp4-muxer}, &1)
           )
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

  @tag native_poster_codec: true
  test "poster PNG encoder leaves studio startup until export", %{tmp_dir: dir} do
    build!(dir, ["--minify"])

    outputs =
      Path.join(dir, "meta.json") |> File.read!() |> Jason.decode!() |> Map.fetch!("outputs")

    {root, _} =
      Enum.find(outputs, fn {_, info} -> Map.has_key?(info["inputs"], "js/poster/runtime.js") end)

    graph =
      for path <- eager(outputs, [root], MapSet.new()),
          input <- Map.keys(outputs[path]["inputs"]),
          do: input

    refute Enum.any?(graph, &String.contains?(&1, "fflate"))
  end

  test "production closures measure actual emitted bytes and keep export codecs lazy", %{
    tmp_dir: dir
  } do
    build!(dir, ["--minify"])

    outputs =
      Path.join(dir, "meta.json") |> File.read!() |> Jason.decode!() |> Map.fetch!("outputs")

    _chunks =
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
             engine_inputs(closure_inputs.(roots.app)),
             &Regex.match?(~r{js/(map|poster|video)/|h3-js|fflate|mp4-muxer}, &1)
           )

    refute Enum.any?(
             engine_inputs(closure_inputs.(roots.map)),
             &Regex.match?(~r{js/poster/(runtime|export)|js/video/|h3-js|fflate|mp4-muxer}, &1)
           )

    refute "js/map/ui/retry.js" in closure_inputs.(roots.map)

    refute Enum.any?(closure_inputs.(roots.poster), &String.contains?(&1, "mp4-muxer"))
    refute Enum.any?(closure_inputs.(roots.video), &String.contains?(&1, "fflate"))
    graph = inputs(dir)
    assert Enum.any?(graph, &String.contains?(&1, "fflate"))
    assert Enum.any?(graph, &String.contains?(&1, "mp4-muxer"))

    sizes =
      Map.new(roots, fn {name, root} ->
        {name, Dawarich.Build.NativeAssetBudget.measure(outputs, root, dir)}
      end)

    assert Dawarich.Build.NativeAssetBudget.within?(sizes)

    IO.puts("NATIVE_BUILD_BYTES " <> Jason.encode!(sizes))
  end

  test "production byte gate rejects an oversized emitted banner using actual files", %{
    tmp_dir: dir
  } do
    banner = Jason.encode!(String.duplicate("x", 200_001)) <> ";"
    build!(dir, ["--minify", "--banner:js=" <> banner])

    outputs =
      Path.join(dir, "meta.json") |> File.read!() |> Jason.decode!() |> Map.fetch!("outputs")

    root =
      Enum.find_value(outputs, fn {path, _} -> if Path.basename(path) == "app.js", do: path end)

    dishonest = Map.new(outputs, fn {path, info} -> {path, Map.put(info, "bytes", 1)} end)
    measured = Dawarich.Build.NativeAssetBudget.measure(dishonest, root, dir)
    assert measured.raw > 200_000

    sizes =
      Map.new(Dawarich.Build.NativeAssetBudget.caps(), fn {name, cap} ->
        {name, Map.put(cap, :chunks, 1)}
      end)

    refute Dawarich.Build.NativeAssetBudget.within?(Map.put(sizes, :app, measured))
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

  test "native Places imports add bounded eager JS and no map or legacy graph", %{tmp_dir: dir} do
    build!(dir)

    outputs =
      dir |> Path.join("meta.json") |> File.read!() |> Jason.decode!() |> Map.fetch!("outputs")

    {app, _} = Enum.find(outputs, fn {path, _} -> Path.basename(path) == "app.js" end)

    inputs =
      for path <- eager(outputs, [app], MapSet.new()),
          {input, meta} <- outputs[path]["inputs"],
          do: {input, meta["bytesInOutput"]}

    refute Enum.any?(inputs, fn {input, _} ->
             Regex.match?(~r/maplibre|app\/javascript|@hotwired|rails_bridge/i, input)
           end)

    bytes =
      inputs
      |> Enum.filter(fn {input, _} ->
        input in @places_inputs
      end)
      |> Enum.map(&elem(&1, 1))
      |> Enum.sum()

    assert bytes in 1..@places_cap
  end

  test "native jobs eager and lazy module graph excludes Rails transport runtimes", %{
    tmp_dir: dir
  } do
    inputs = dir |> build!() |> inputs()
    assert Enum.any?(inputs, &String.ends_with?(&1, "uploaders/direct.js"))
    assert Enum.any?(inputs, &String.ends_with?(&1, "hooks/archive_checksum.js"))

    refute Enum.any?(
             inputs,
             &Regex.match?(
               ~r/@hotwired|stimulus|turbo|rails_bridge|actioncable|activestorage/i,
               &1
             )
           )

    refute Enum.any?(inputs, &String.contains?(&1, "app/javascript"))
  end

  test "native family sharing and public eager and lazy modules exclude Rails transports", %{
    tmp_dir: dir
  } do
    inputs = dir |> build!() |> inputs()

    for hook <-
          ~w(map/shared/family_map.js hooks/family_confirm.js hooks/sharing_controls.js map/shared/shared_map.js map/shared/shared_replay.js hooks/clipboard.js),
        do: assert(Enum.any?(inputs, &String.ends_with?(&1, hook)))

    refute Enum.any?(
             inputs,
             &Regex.match?(
               ~r/@hotwired|stimulus|turbo|rails_bridge|actioncable|activestorage/i,
               &1
             )
           )

    refute Enum.any?(inputs, &String.contains?(&1, "app/javascript"))
  end

  test "M4 features retain independent eager byte caps", %{tmp_dir: dir} do
    bytes = dir |> build!() |> app_input_bytes()

    for {inputs, measured} <- @m4_inputs do
      assert Enum.sum(Map.values(Map.take(bytes, inputs))) <= measured + 1024, inspect(inputs)
    end
  end

  test "public and family map runtimes stay outside the first-paint graph", %{tmp_dir: dir} do
    bytes = dir |> build!() |> app_input_bytes()

    for input <-
          ~w(js/map/shared/shared_map.js js/map/shared/shared_replay.js js/map/shared/shared_routes.js js/map/shared/shared_route_segmenter.js js/map/shared/family_map.js node_modules/spark-md5/spark-md5.js),
        do: refute(Map.has_key?(bytes, input), input)
  end

  test "archive preparation and ZIP dependencies stay lazy within its independent feature budget",
       %{
         tmp_dir: dir
       } do
    assert 0 ==
             Esbuild.install_and_run(:native, [
               "--outdir=#{dir}",
               "--metafile=#{Path.join(dir, "meta.json")}",
               "--log-level=warning",
               "--minify"
             ])

    outputs =
      dir |> Path.join("meta.json") |> File.read!() |> Jason.decode!() |> Map.fetch!("outputs")

    {app, _} = Enum.find(outputs, fn {path, _} -> Path.basename(path) == "app.js" end)
    paths = eager(outputs, [app], MapSet.new())
    eager_inputs = for path <- paths, {input, _} <- outputs[path]["inputs"], do: input
    refute Enum.any?(eager_inputs, &String.contains?(&1, "prepare_file.js"))
    refute Enum.any?(eager_inputs, &String.contains?(&1, "fflate"))

    assert Enum.any?(Map.keys(outputs), fn path ->
             Enum.any?(Map.keys(outputs[path]["inputs"]), &String.contains?(&1, "fflate"))
           end)

    bytes =
      app_input_bytes(dir)
      |> Map.take(~w(js/hooks/archive_checksum.js js/uploaders/direct.js))
      |> Map.values()
      |> Enum.sum()

    assert bytes <= 8_416 + 1024
  end

  defp app_input_bytes(dir) do
    outputs =
      dir |> Path.join("meta.json") |> File.read!() |> Jason.decode!() |> Map.fetch!("outputs")

    {app, _} = Enum.find(outputs, fn {path, _} -> Path.basename(path) == "app.js" end)

    for path <- eager(outputs, [app], MapSet.new()),
        {input, meta} <- outputs[path]["inputs"],
        reduce: %{},
        do: (acc -> Map.update(acc, input, meta["bytesInOutput"], &(&1 + meta["bytesInOutput"])))
  end

  test "charts and editor stay lazy with a bounded eager stub and an independent public entry", %{
    tmp_dir: dir
  } do
    build!(dir)

    outputs =
      dir |> Path.join("meta.json") |> File.read!() |> Jason.decode!() |> Map.fetch!("outputs")

    {app, _} = Enum.find(outputs, fn {path, _} -> Path.basename(path) == "app.js" end)

    for sources <- [["chart", "heatmap"], ["rich_text", "editor"]] do
      bytes =
        for path <- eager(outputs, [app], MapSet.new()),
            {input, %{"bytesInOutput" => bytes}} <- outputs[path]["inputs"],
            Enum.any?(sources, &String.contains?(input, &1)),
            reduce: 0,
            do: (sum -> sum + bytes)

      assert bytes in 1..2048
    end

    assert File.regular?(Path.join(dir, "public_charts.js"))
    refute File.read!(Path.join(dir, "public_charts.js")) =~ "LiveSocket"
    assert Enum.any?(inputs(dir), &String.contains?(&1, "chartkick"))
    refute Enum.any?(inputs(dir), &String.contains?(&1, "actiontext"))
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

    refute Enum.any?(engine_inputs(eager_inputs), &Regex.match?(~r{js/(map/|poster/|video/)}, &1))
    assert Enum.any?(inputs(dir), &String.contains?(&1, "map/runtime/host.js"))
  end

  test "native map chunks contain no Rails controller or Hotwire input", %{tmp_dir: dir} do
    build!(dir)
    graph = inputs(dir)
    assert Enum.any?(graph, &String.contains?(&1, "map/hooks/map.js"))
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
    assert Plug.Conn.get_resp_header(conn, "cache-control") == ["public"]
    versioned = DawarichWeb.Endpoint.call(conn(:get, "/native/" <> probe <> "?vsn=1"), [])
    assert versioned.status == 200

    assert Plug.Conn.get_resp_header(versioned, "cache-control") == [
             "public, max-age=31536000, immutable"
           ]

    head = DawarichWeb.Endpoint.call(conn(:head, "/native/" <> probe), [])
    assert head.status == 200
    assert head.resp_body == ""
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

    Dawarich.Build.NativeAssets.build!(source_root, public)
    Phoenix.Digester.compile(public, public, true)

    paths =
      for name <- ~w(maplibre-gl.mjs maplibre-gl-shared.mjs maplibre-gl-worker.mjs),
          do: {"/maplibre/6.4.1/" <> name, "text/javascript"}

    paths =
      paths ++
        [
          {"/maps_maplibre/styles/light.json", "application/json"},
          {"/maps_maplibre/styles/dark.json", "application/json"}
        ] ++
        Enum.map(font_paths, &{DawarichWeb.Assets.stylesheet_path(public, &1), "font/woff2"}) ++
        [{DawarichWeb.Assets.stylesheet_path(public, "mapbox-gl-rtl-text.js"), "text/javascript"}]

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
