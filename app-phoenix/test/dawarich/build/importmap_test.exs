defmodule Dawarich.Build.ImportmapTest do
  use ExUnit.Case, async: true

  alias Dawarich.Build.Importmap

  @moduletag :tmp_dir

  defp file!(root, path, body \\ "") do
    full = Path.join(root, path)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, body)
  end

  test "pins first in file order, then each pin_all_from tree sorted, index names folded", %{
    tmp_dir: root
  } do
    file!(root, "config/importmap.rb", """
    # frozen_string_literal: true

    pin_all_from 'app/javascript/controllers', under: 'controllers'
    pin 'application', preload: true
    pin "maplibre-gl", to: "/maplibre/6.4.1/maplibre-gl.mjs" # served from public
    pin 'trix'
    """)

    for f <-
          ~w(index.js b_controller.js nested/index.js nested/a_controller.js skip.mjs legacy.jsm),
        do: file!(root, "app/javascript/controllers/" <> f)

    assets = %{
      "application.js" => "application-1.js",
      "trix.js" => "trix-2.js",
      "controllers/b_controller.js" => "controllers/b_controller-3.js",
      "controllers/index.js" => "controllers/index-4.js",
      "controllers/legacy.jsm" => "controllers/legacy-5.jsm",
      "controllers/nested/a_controller.js" => "controllers/nested/a_controller-6.js",
      "controllers/nested/index.js" => "controllers/nested/index-7.js"
    }

    assert IO.iodata_to_binary(Importmap.export(root, assets)) == """
           {
             "imports": {
               "application": "/assets/application-1.js",
               "maplibre-gl": "/maplibre/6.4.1/maplibre-gl.mjs",
               "trix": "/assets/trix-2.js",
               "controllers/b_controller": "/assets/controllers/b_controller-3.js",
               "controllers": "/assets/controllers/index-4.js",
               "controllers/legacy": "/assets/controllers/legacy-5.jsm",
               "controllers/nested/a_controller": "/assets/controllers/nested/a_controller-6.js",
               "controllers/nested": "/assets/controllers/nested/index-7.js"
             }
           }\
           """
  end

  test "refuses importmap DSL the parser does not know", %{tmp_dir: root} do
    for line <- [
          "enable_integrity!",
          "pin 'x', integrity: 'sha384-y'",
          "pin_all_from 'a', under: c"
        ] do
      file!(root, "config/importmap.rb", line <> "\n")
      assert_raise ArgumentError, ~r/unsupported/, fn -> Importmap.export(root, %{}) end
    end
  end

  test "a pin missing from the manifest fails the build", %{tmp_dir: root} do
    file!(root, "config/importmap.rb", "pin 'gone'\n")

    assert_raise ArgumentError, ~r/gone\.js/, fn -> Importmap.export(root, %{}) end
  end
end
