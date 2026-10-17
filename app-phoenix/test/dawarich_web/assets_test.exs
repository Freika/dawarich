defmodule DawarichWeb.AssetsTest do
  use ExUnit.Case, async: true
  alias DawarichWeb.Assets

  @tag :tmp_dir
  test "stylesheet paths come from the native digest, or stay logical without one", %{
    tmp_dir: root
  } do
    assert Assets.stylesheet_path(root, "tailwind.css") == "/native/tailwind.css"

    File.write!(
      Path.join(root, "cache_manifest.json"),
      Jason.encode!(%{"latest" => %{"native/tailwind.css" => "native/tailwind-0123abcd.css"}})
    )

    assert Assets.stylesheet_path(root, "tailwind.css") == "/native/tailwind-0123abcd.css"
    assert Assets.stylesheet_path(root, "missing.css") == "/native/missing.css"
  end
end
