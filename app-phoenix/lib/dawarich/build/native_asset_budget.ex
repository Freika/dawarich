defmodule Dawarich.Build.NativeAssetBudget do
  @moduledoc false
  @caps %{
    app: %{raw: 200_000, gzip: 65_000},
    map: %{raw: 132_500, gzip: 46_000},
    poster: %{raw: 60_000, gzip: 26_000},
    video: %{raw: 100_000, gzip: 36_000}
  }
  def caps, do: @caps

  def within?(sizes) when is_map(sizes) and map_size(sizes) == 4 do
    Enum.all?(@caps, fn {name, cap} ->
      case sizes[name] do
        %{raw: raw, gzip: gzip, chunks: chunks}
        when is_integer(raw) and is_integer(gzip) and is_integer(chunks) ->
          raw > 0 and raw <= cap.raw and gzip > 0 and gzip <= cap.gzip and chunks > 0

        _ ->
          false
      end
    end)
  end

  def within?(_), do: false

  def measure(outputs, root, directory) do
    files = closure(outputs, [root], MapSet.new())

    Enum.reduce(files, %{raw: 0, gzip: 0, chunks: MapSet.size(files)}, fn path, sizes ->
      bytes = File.read!(Path.join(directory, Path.basename(path)))

      %{
        sizes
        | raw: sizes.raw + byte_size(bytes),
          gzip: sizes.gzip + byte_size(:zlib.gzip(bytes))
      }
    end)
  end

  defp closure(_outputs, [], seen), do: seen

  defp closure(outputs, [path | rest], seen) do
    if MapSet.member?(seen, path) do
      closure(outputs, rest, seen)
    else
      imports =
        for %{"kind" => "import-statement", "path" => imported} <- outputs[path]["imports"],
            Map.has_key?(outputs, imported),
            do: imported

      closure(outputs, imports ++ rest, MapSet.put(seen, path))
    end
  end
end
