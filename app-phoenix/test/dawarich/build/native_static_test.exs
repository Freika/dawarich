defmodule Dawarich.Build.NativeStaticTest do
  use ExUnit.Case, async: true
  import Plug.Test
  alias Dawarich.Build.NativeAssets
  alias DawarichWeb.Assets

  @moduletag :tmp_dir

  defp sources!(dir) do
    original = Dawarich.RailsRoot.root()
    root = Path.join(dir, "source")

    for path <-
          ~w(app/assets vendor/assets app-phoenix/assets/css app-phoenix/assets/static app-phoenix/priv/tailwind app-phoenix/lib config/locales config/achievements) do
      File.mkdir_p!(Path.dirname(Path.join(root, path)))
      File.cp_r!(Path.join(original, path), Path.join(root, path))
    end

    manifest = File.read!("assets/native-static.json") |> Jason.decode!()

    for [path, _] <- manifest["copies"] do
      target = Path.join(root, path)
      File.mkdir_p!(Path.dirname(target))
      File.cp!(Path.join(original, path), target)
    end

    for path <-
          ~w(app-phoenix/assets/native-static.json app-phoenix/assets/tailwind.config.cjs config/achievements.yml) do
      File.cp!(Path.join(original, path), Path.join(root, path))
    end

    for path <-
          ~w(app-phoenix/priv/time_zones.json config/shared_link_wordlist.txt lib/assets/countries.geojson.gz lib/assets/admin1_world.geojson) do
      File.mkdir_p!(Path.dirname(Path.join(root, path)))
      File.cp!(Path.join(original, path), Path.join(root, path))
    end

    File.ln_s!(
      Path.expand("assets/node_modules"),
      Path.join(root, "app-phoenix/assets/node_modules")
    )

    root
  end

  test "native assets build with Rails frontend configuration absent", %{tmp_dir: dir} do
    root = sources!(dir)
    static = Path.join(dir, "static")
    refute File.exists?(Path.join(root, "config/importmap.rb"))
    File.rm_rf!(Path.join(root, "app/assets/config"))
    assert NativeAssets.build!(root, static) == :ok

    for name <-
          ~w(tailwind.css inter-font.css application.css achievements.css achievements_spectral.css achievements_unlocks.css logo.svg poster/inter-400.woff2 mapbox-gl-rtl-text.js) do
      assert File.stat!(Path.join(static, "native/" <> name)).size > 0
    end

    refute File.exists?(Path.join(root, "app/javascript"))
    css = File.read!(Path.join(static, "native/tailwind.css"))
    assert css =~ ~S(.min-w-0{min-width:0})
    assert css =~ ~S(.bg-secondary\/10{background-color:)
  end

  test "missing declared native asset fails build before release", %{tmp_dir: dir} do
    root = sources!(dir)
    File.rm!(Path.join(root, "app/assets/fonts/poster/inter-400.woff2"))
    assert_raise File.Error, fn -> NativeAssets.build!(root, Path.join(dir, "static")) end
  end

  test "native stylesheet fonts and lazy worker URLs resolve from the production digest", %{
    tmp_dir: dir
  } do
    root = sources!(dir)
    static = Path.join(dir, "static")
    NativeAssets.build!(root, static)
    Phoenix.Digester.compile(static, static, true)
    css_path = Assets.stylesheet_path(static, "inter-font.css")
    assert css_path =~ ~r{^/native/inter-font-[a-f0-9]+\.css$}
    options = Plug.Static.init(at: "/", from: static, gzip: true)
    response = Plug.Static.call(conn(:get, css_path), options)
    assert response.status == 200
    assert response.resp_body =~ "font-face"

    for [url] <-
          Regex.scan(~r/url\(['"]?([^)'"\s]+)['"]?\)/, response.resp_body,
            capture: :all_but_first
          ) do
      path = URI.merge("http://static.test" <> css_path, url).path
      font = Plug.Static.call(conn(:get, path), options)
      assert font.status == 200
      assert Plug.Conn.get_resp_header(font, "content-type") == ["font/woff2"]
      assert byte_size(font.resp_body) > 0
      assert Plug.Static.call(conn(:head, path), options).status == 200
    end

    public = Dawarich.RailsRoot.join("public")
    public_options = Plug.Static.init(at: "/", from: public)

    for file <- ~w(maplibre-gl.mjs maplibre-gl-worker.mjs) do
      path = "/maplibre/6.4.1/" <> file
      worker = Plug.Static.call(conn(:get, path), public_options)
      assert worker.status == 200
      assert worker.resp_body =~ "./maplibre-gl-shared.mjs"
      sibling = URI.merge("http://static.test" <> path, "./maplibre-gl-shared.mjs").path
      assert Plug.Static.call(conn(:get, sibling), public_options).status == 200
    end
  end

  test "runtime data exports build without frontend configuration", %{tmp_dir: dir} do
    root = sources!(dir)
    File.rm_rf!(Path.join(root, "app/assets/config"))
    out = Path.join(dir, "data")
    Mix.Tasks.Dawarich.BuildInputs.run(["--root", root, "--out", out])
    assert Jason.decode!(File.read!(Path.join(out, "tmp/phoenix/i18n.json")))["en"]

    assert File.read!(Path.join(out, "tmp/phoenix/time_zones.json")) ==
             File.read!("priv/time_zones.json")

    refute File.exists?(Path.join(out, "tmp/phoenix/importmap.json"))
    refute File.exists?(Path.join(out, "config/sprockets-manifest.json"))
    refute File.exists?(Path.join(out, "public/assets"))
  end
end
