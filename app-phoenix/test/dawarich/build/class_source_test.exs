defmodule Dawarich.Build.ClassSourceTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir
  @css "ef1b8aa576696d4f892652e810d7665f147493a4efb9b3523c610402c4574d73"

  @tag :fix_image_tailwind
  test "Docker asset stage closes over Tailwind class sources and preserves CSS bytes", %{
    tmp_dir: tmp
  } do
    root = Dawarich.Build.root()

    copies =
      Path.join(root, "docker/Dockerfile")
      |> File.read!()
      |> String.split("AS phoenix_builder", parts: 2)
      |> List.last()
      |> String.split("WORKDIR /src", parts: 2)
      |> List.last()
      |> String.split("RUN BROWSERSLIST_IGNORE_OLD_DATA", parts: 2)
      |> List.first()
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "COPY "))

    for copy <- copies do
      paths = copy |> String.replace_prefix("COPY ", "") |> String.split()
      sources = Enum.drop(paths, -1)
      destination = List.last(paths)

      for source <- sources do
        target =
          if length(sources) > 1 or String.ends_with?(destination, "/"),
            do: Path.join(destination, Path.basename(source)),
            else: destination

        target = Path.join(tmp, target)
        File.mkdir_p!(Path.dirname(target))
        File.cp_r!(Path.join(root, source), target)
      end
    end

    styles = compile_styles(root, tmp)
    assert styles =~ ~S(.bg-secondary\/10{background-color:)
    assert styles =~ ~S(.hover\:bg-\[\#383f47\]:hover{)
    assert Base.encode16(:crypto.hash(:sha256, styles), case: :lower) == @css
  end

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

    styles = compile_styles(root, tmp)
    assert styles =~ ~S(.bg-secondary\/10{background-color:)
    assert styles =~ ~S(.hover\:bg-\[\#383f47\]:hover{)
  end

  defp compile_styles(root, tmp) do
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
    File.read!(css)
  end
end
