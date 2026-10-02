defmodule DawarichWeb.AssetsTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Plug.Conn, only: [get_resp_header: 2]

  alias DawarichWeb.Assets

  @endpoint DawarichWeb.Endpoint

  @tag :tmp_dir
  test "stylesheet paths come from Sprockets' manifest, or stay logical without one", %{
    tmp_dir: root
  } do
    assert Assets.stylesheet_path(root, "tailwind.css") == "/assets/tailwind.css"

    File.mkdir_p!(Path.join(root, "public/assets"))
    manifest = %{"assets" => %{"tailwind.css" => "tailwind-0123abcd.css"}}

    File.write!(
      Path.join(root, "public/assets/.sprockets-manifest-9f8e.json"),
      Jason.encode!(manifest)
    )

    assert Assets.stylesheet_path(root, "tailwind.css") == "/assets/tailwind-0123abcd.css"
    assert Assets.stylesheet_path(root, "missing.css") == "/assets/missing.css"
  end

  @tag :tmp_dir
  test "Rails configured manifest wins over a conflicting legacy public manifest", %{
    tmp_dir: root
  } do
    File.mkdir_p!(Path.join(root, "config"))
    File.mkdir_p!(Path.join(root, "public/assets"))
    configured = "tailwind-663f95bd251f7502effd9b05f386e045634a15c990a237e20c0f647c57c46e99.css"

    File.write!(
      Path.join(root, "config/sprockets-manifest.json"),
      Jason.encode!(%{"assets" => %{"tailwind.css" => configured}})
    )

    File.write!(
      Path.join(root, "public/assets/.sprockets-manifest-old.json"),
      Jason.encode!(%{"assets" => %{"tailwind.css" => "tailwind-older-public.css"}})
    )

    assert Assets.stylesheet_path(root, "tailwind.css") == "/assets/" <> configured
    assert Assets.stylesheet_path(root, "missing.css") == "/assets/missing.css"
    File.rm!(Path.join(root, "config/sprockets-manifest.json"))
    assert Assets.stylesheet_path(root, "tailwind.css") == "/assets/tailwind-older-public.css"
  end

  @tag :tmp_dir
  test "Source configured precompile manifest resolves with no public wildcard manifest", %{
    tmp_dir: root
  } do
    File.mkdir_p!(Path.join(root, "config"))

    configured =
      "application-0a04ba66afa1fa29d9079d22048b5ff5a211f1b597cc569f315784b4f21e68d6.css"

    File.write!(
      Path.join(root, "config/sprockets-manifest.json"),
      Jason.encode!(%{"assets" => %{"application.css" => configured}})
    )

    assert Assets.stylesheet_path(root, "application.css") == "/assets/" <> configured
  end

  test "Phoenix serves its own scripts, immutably when versioned" do
    %{app: app} = Assets.script_versions()

    conn = get(build_conn(), "/phoenix/js/app.js?vsn=#{app}")
    assert conn.status == 200
    assert conn.resp_body =~ "LiveSocket"
    assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]

    assert get(build_conn(), "/phoenix/js/phoenix_live_view.esm.js").status == 200
    assert get(build_conn(), "/phoenix/js/phoenix.mjs").status == 200
  end

  @tag :tmp_dir
  test "Rails' imports come from the phoenix:importmap export, or are empty without one", %{
    tmp_dir: dir
  } do
    path = Path.join(dir, "importmap.json")
    assert Assets.read_imports(path) == %{}

    File.write!(
      path,
      Jason.encode!(%{"imports" => %{"chartkick" => "/assets/chartkick-0123abcd.js"}})
    )

    assert Assets.read_imports(path) == %{"chartkick" => "/assets/chartkick-0123abcd.js"}
    File.write!(path, "{")
    assert Assets.read_imports(path) == %{}
  end

  test "map_shell.js is served, versioned and in Phoenix's importmap" do
    versions = DawarichWeb.Assets.script_versions()
    assert versions.map_shell =~ ~r/\A[A-Za-z0-9_-]{22}\z/

    imports = DawarichWeb.Layouts.importmap() |> Jason.decode!() |> Map.fetch!("imports")
    assert imports["map_shell"] == "/phoenix/js/map_shell.js?vsn=#{versions.map_shell}"

    conn =
      Phoenix.ConnTest.dispatch(
        Phoenix.ConnTest.build_conn(),
        DawarichWeb.Endpoint,
        :get,
        "/phoenix/js/map_shell.js",
        nil
      )

    assert conn.status == 200
    assert conn.resp_body =~ ~s(import "@hotwired/turbo-rails")
    assert conn.resp_body =~ ~s{lazyLoadControllersFrom("controllers", application, element)}
  end

  test "rails_bridge.js is served, versioned, in Phoenix's importmap and imported by app.js" do
    versions = Assets.script_versions()
    assert versions.rails_bridge =~ ~r/\A[A-Za-z0-9_-]{22}\z/

    imports = DawarichWeb.Layouts.importmap() |> Jason.decode!() |> Map.fetch!("imports")
    assert imports["rails_bridge"] == "/phoenix/js/rails_bridge.js?vsn=#{versions.rails_bridge}"

    conn = get(build_conn(), "/phoenix/js/rails_bridge.js?vsn=#{versions.rails_bridge}")
    assert conn.status == 200
    assert conn.resp_body =~ "export const RailsStimulus"
    assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]

    assert File.read!("priv/static/js/app.js") =~ ~s(from "rails_bridge")
    assert File.read!("priv/static/js/map_shell.js") =~ ~s(from "rails_bridge")
  end

  test "rails_bridge.js lists each island's Stimulus application in window.StimulusIslands while it runs" do
    source = File.read!("priv/static/js/rails_bridge.js")

    assert source =~ "window.StimulusIslands = islands"
    assert source =~ ~r/Application\.start\(element\)\n\s+islands\.add\(app\)/
    assert source =~ ~r/app\.stop\(\)\n\s+islands\.delete\(app\)/
  end

  test "Phoenix's scripts stay under 300 lines and carry no comments" do
    for file <- Path.wildcard("priv/static/js/*.js") do
      source = File.read!(file)
      assert source |> String.trim_trailing() |> String.split("\n") |> length() < 300, file
      refute source =~ ~r{^\s*//}m, file
    end
  end
end
