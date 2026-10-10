defmodule Dawarich.Build.NativeAssetsTest do
  use ExUnit.Case, async: true
  import Plug.Test

  @moduletag :tmp_dir

  @http_chrome_cap 2 * 1024
  @places_cap 2 * 1024
  @other_slack 1024
  @chrome_inputs ~w(js/analytics_events.js js/hooks/achievement_unlocks.js js/hooks/changelog_widget.js)
  @chrome_base_bytes 6_707 + 548
  @places_inputs ~w(js/hooks/place_draft.js js/hooks/ordinary_dialog.js)
  @m5_inputs ~w(js/hooks/chart.js js/hooks/heatmap.js js/hooks/rich_text.js)
  @other_base_bytes 335_463 - 16_713 - 1_844 - 1_632 - 232
  @m4_inputs [
    {~w(js/hooks/archive_checksum.js js/uploaders/direct.js), 8416},
    {~w(js/hooks/credential_qr.js js/hooks/credential_value.js), 4256},
    {~w(js/hooks/family_confirm.js js/hooks/family_invitation_clipboard.js), 2918},
    {~w(js/hooks/sharing_controls.js js/hooks/clipboard.js), 6365},
    {~w(js/hooks/lazy_maps.js js/hooks/shared_erase.js js/hooks/index.js), 3748}
  ]

  @tag trix_pin: true
  test "native editor builds pinned Trix with no ActionText transport", %{tmp_dir: dir} do
    manifest = File.read!("assets/package.json") |> Jason.decode!()
    assert manifest["dependencies"]["trix"] == "2.1.19"
    graph = dir |> build!() |> inputs()
    assert Enum.any?(graph, &String.contains?(&1, "node_modules/trix/"))
    refute Enum.any?(graph, &Regex.match?(~r/@rails|actiontext|activestorage/i, &1))
  end

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
    bytes =
      dir
      |> build!()
      |> app_input_bytes()
      |> Map.drop(
        @chrome_inputs ++ @places_inputs ++ @m5_inputs ++ Enum.flat_map(@m4_inputs, &elem(&1, 0))
      )

    assert Enum.sum(Map.values(bytes)) <= @other_base_bytes + @other_slack
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
          ~w(family_map.js family_confirm.js sharing_controls.js shared_map.js shared_replay.js clipboard.js),
        do: assert(Enum.any?(inputs, &String.ends_with?(&1, "hooks/" <> hook)))

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
          ~w(js/hooks/shared_map.js js/hooks/shared_replay.js js/hooks/shared_routes.js js/hooks/shared_route_segmenter.js js/hooks/family_map.js node_modules/spark-md5/spark-md5.js),
        do: refute(Map.has_key?(bytes, input), input)
  end

  test "archive preparation and ZIP dependencies stay lazy within the shared gzip budget", %{
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

    gzip =
      Enum.reduce(paths, 0, fn path, size ->
        size + byte_size(:zlib.gzip(File.read!(Path.expand(path, "assets"))))
      end)

    assert gzip <= 51_397 + 5 * 1024
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
