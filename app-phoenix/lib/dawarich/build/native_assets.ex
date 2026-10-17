defmodule Dawarich.Build.NativeAssets do
  @moduledoc false

  @styles ~w(application.css achievements.css achievements_spectral.css achievements_unlocks.css)
  @outputs ~w(tailwind.css inter-font.css application.css achievements.css achievements_spectral.css achievements_unlocks.css)
  @urls ~r/url\(\s*["']?([^\s)'";]+)["']?\s*\)/

  def build!(root, static) do
    assets = Path.join(root, "app-phoenix/assets")
    out = Path.join(static, "native")
    manifest = Path.join(assets, "native-static.json") |> File.read!() |> Jason.decode!()
    File.mkdir_p!(out)

    for [source, target] <- manifest["copies"] do
      destination = Path.join(out, target)
      File.mkdir_p!(Path.dirname(destination))
      File.stat!(Path.join(root, source))
      File.cp!(Path.join(root, source), destination)
    end

    File.cp!(
      Path.join(root, "vendor/assets/stylesheets/inter-font.css"),
      Path.join(out, "inter-font.css")
    )

    run!(
      Path.join(assets, "node_modules/.bin/tailwindcss"),
      [
        "-i",
        Path.join(root, "app/assets/stylesheets/application.tailwind.css"),
        "-c",
        "tailwind.config.cjs",
        "--minify",
        "-o",
        Path.join(out, "tailwind.css")
      ],
      assets
    )

    entries = [
      "application=css/application.css"
      | Enum.map(
          tl(@styles),
          &(Path.rootname(&1) <> "=" <> Path.join(root, "app/assets/stylesheets/" <> &1))
        )
    ]

    run!(
      Esbuild.bin_path(),
      entries ++
        [
          "--bundle",
          "--minify",
          "--external:*.woff2",
          "--external:*.woff",
          "--outdir=#{out}",
          "--log-level=warning"
        ],
      assets
    )

    validate!(static)
  end

  def validate!(static) do
    for name <- @outputs do
      path = Path.join(static, "native/" <> name)
      text = File.read!(path)
      if byte_size(text) == 0, do: raise(ArgumentError, "Empty native stylesheet: #{name}")

      for [url] <- Regex.scan(@urls, text, capture: :all_but_first),
          uri = URI.parse(url),
          is_nil(uri.scheme),
          is_nil(uri.host),
          not String.starts_with?(URI.decode(url), "#") do
        target =
          if String.starts_with?(uri.path, "/"),
            do: Path.join(static, String.trim_leading(uri.path, "/")),
            else: Path.expand(uri.path, Path.dirname(path))

        File.stat!(target)
      end
    end

    paths = Path.wildcard(Path.join(static, "native/**/*.{js,mjs}"))

    case Dawarich.Build.NativeDependencyGraph.audit_files(paths) do
      [] -> :ok
      findings -> raise ArgumentError, "Forbidden native static scripts: #{inspect(findings)}"
    end
  end

  defp run!(command, args, cwd) do
    case System.cmd(command, args,
           cd: cwd,
           env: [{"BROWSERSLIST_IGNORE_OLD_DATA", "1"}],
           stderr_to_stdout: true
         ) do
      {_, 0} -> :ok
      {message, _} -> raise ArgumentError, "Native assets failed: #{message}"
    end
  end
end
