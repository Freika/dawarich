defmodule Dawarich.Build.ClassSourceTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  @tag :a12f4_a22_1
  test "native class sources preserve required styles without Rails templates", %{tmp_dir: tmp} do
    root = Dawarich.Build.root()
    retained = Path.join(root, "app-phoenix/priv/tailwind/retained_classes.html")
    assert File.regular?(retained)
    config = File.read!(Path.join(root, "config/tailwind.config.js"))
    refute config =~ "./app/helpers/"
    refute config =~ "./app/views/"

    for path <-
          ~w(config/tailwind.config.js app/assets app/javascript app-phoenix/lib app-phoenix/priv/tailwind) do
      target = Path.join(tmp, path)
      File.mkdir_p!(Path.dirname(target))
      File.cp_r!(Path.join(root, path), target)
    end

    File.ln_s!(Path.join(root, "node_modules"), Path.join(tmp, "node_modules"))
    css = Path.join(tmp, "tailwind.css")

    {output, status} =
      System.cmd(
        Path.join(root, "node_modules/.bin/tailwindcss"),
        [
          "-i",
          "app/assets/stylesheets/application.tailwind.css",
          "-o",
          css,
          "-c",
          "config/tailwind.config.js",
          "--minify"
        ],
        cd: tmp,
        env: [{"BROWSERSLIST_IGNORE_OLD_DATA", "1"}],
        stderr_to_stdout: true
      )

    assert status == 0, output
    styles = File.read!(css)
    assert styles =~ ~S(.bg-secondary\/10{background-color:)
    assert styles =~ ~S(.hover\:bg-\[\#383f47\]:hover{)
  end
end
