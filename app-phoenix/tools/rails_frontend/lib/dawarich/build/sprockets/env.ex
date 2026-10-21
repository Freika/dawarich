defmodule Dawarich.Build.Sprockets.Env do
  @moduledoc false

  defstruct [:paths]

  @registered ~w(.js .json .rb .xml .webmanifest .css .html .htm .txt .text .yml .yaml .ico .bmp .gif .webp
                 .png .jpg .jpeg .tiff .tif .svg .webm .snd .au .aiff .mp3 .mp2 .m2a .m3a .ogx .ogg .oga
                 .midi .mid .avi .wav .wave .mp4 .m4v .aac .m4a .flac .eot .otf .ttf .woff .woff2 .map .erb
                 .rhtml .rxml)

  @kinds %{
    ".js" => :js,
    ".css" => :css,
    ".map" => :map,
    ".svg" => :svg,
    ".ico" => :ico,
    ".xml" => :xml
  }
  @accept %{".js" => :js, ".css" => :css}
  @unmodelled ~w(.json .html .htm .yml .yaml .eot .otf .ttf .webmanifest)

  def new(root) do
    groups = Enum.flat_map(~w(app/assets lib/assets vendor/assets), &subdirs(Path.join(root, &1)))

    scripts =
      for dir <- ~w(app/javascript vendor/javascript),
          File.dir?(Path.join(root, dir)),
          do: Path.join(root, dir)

    %__MODULE__{paths: groups ++ scripts}
  end

  def accept(ext), do: Map.fetch!(@accept, ext)

  def kind(path), do: Map.get(@kinds, Path.extname(path), :raw)

  def resolve(env, path, accept, base) do
    cond do
      String.starts_with?(path, ["./", "../"]) ->
        path
        |> Path.expand(base)
        |> candidates(path, accept)
        |> Enum.find_value(fn {file, kind} -> File.regular?(file) && asset(env, file, kind) end)

      String.contains?("/" <> path <> "/", "/../") ->
        nil

      true ->
        Enum.find_value(env.paths, &logical(&1, path, accept))
    end
  end

  def asset(env, file, accept) do
    case Enum.find(env.paths, &String.starts_with?(file, &1 <> "/")) do
      nil -> raise ArgumentError, "#{file} is outside the asset load paths"
      load_path -> describe(file, Path.relative_to(file, load_path), accept)
    end
  end

  def tree(dir, recursive) do
    paths =
      dir |> File.ls!() |> Enum.reject(&hidden?/1) |> Enum.sort() |> Enum.map(&Path.join(dir, &1))

    paths =
      if recursive,
        do: Enum.sort_by(paths, &if(File.dir?(&1), do: &1 <> "/", else: &1)),
        else: paths

    Enum.flat_map(paths, &if(recursive and File.dir?(&1), do: [&1 | tree(&1, true)], else: [&1]))
  end

  defp logical(load_path, path, accept) do
    matches =
      for {file, kind} <- candidates(Path.join(load_path, path), path, accept),
          File.regular?(file),
          asset <- List.wrap(describe(file, Path.relative_to(file, load_path), kind)),
          do: asset

    case matches do
      [] -> nil
      [asset] -> asset
      _ -> raise ArgumentError, "#{path} is ambiguous in #{load_path}"
    end
  end

  defp candidates(base, path, accept) do
    ext = Path.extname(path)

    if ext in @registered do
      [{base, accept}, {base <> ".erb", accept || Map.get(@accept, ext) || kind(path)}]
    else
      for {ext, kind} <- [{".js", :js}, {".css", :css}],
          accept in [nil, kind],
          do: {base <> ext, kind}
    end
  end

  defp describe(file, relative, accept) do
    with %{} = asset <- classify(file, relative, accept) do
      unmodelled!(file, relative)
      asset
    end
  end

  defp unmodelled!(file, relative) do
    extension = relative |> String.replace_suffix(".erb", "") |> Path.extname()

    cond do
      extension in @unmodelled ->
        raise ArgumentError, "#{file}: #{extension} assets are not supported"

      Regex.match?(~r/-[0-9a-zA-Z]{7,128}\.digested/, relative) ->
        raise ArgumentError, "#{file}: pre-digested assets are not supported"

      true ->
        :ok
    end
  end

  defp classify(file, relative, accept) do
    if String.ends_with?(relative, ".erb") do
      inner = String.replace_suffix(relative, ".erb", "")

      cond do
        accept == nil ->
          %{file: file, logical: relative, kind: :raw, erb: false}

        accept == kind(inner) and accept in [:css, :xml] ->
          %{file: file, logical: inner, kind: accept, erb: true}

        accept == kind(inner) ->
          raise ArgumentError, "#{file}: ERB #{accept} assets are not supported"

        true ->
          nil
      end
    else
      kind = kind(relative)
      if accept in [nil, kind], do: %{file: file, logical: relative, kind: kind, erb: false}
    end
  end

  defp subdirs(dir) do
    case File.ls(dir) do
      {:ok, names} ->
        for name <- Enum.sort(names),
            not hidden?(name),
            File.dir?(Path.join(dir, name)),
            do: Path.join(dir, name)

      {:error, _} ->
        []
    end
  end

  defp hidden?(name),
    do:
      String.starts_with?(name, ".") or
        (String.starts_with?(name, "#") and String.ends_with?(name, "#")) or
        String.ends_with?(name, "~")
end
