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

  test "Phoenix serves its own scripts, immutably when versioned" do
    %{app: app} = Assets.script_versions()

    conn = get(build_conn(), "/phoenix/js/app.js?vsn=#{app}")
    assert conn.status == 200
    assert conn.resp_body =~ "LiveSocket"
    assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]

    assert get(build_conn(), "/phoenix/js/phoenix_live_view.esm.js").status == 200
    assert get(build_conn(), "/phoenix/js/phoenix.mjs").status == 200
  end

  test "app.js carries no comments" do
    refute File.read!("priv/static/js/app.js") =~ ~r{^\s*//}m
  end
end
