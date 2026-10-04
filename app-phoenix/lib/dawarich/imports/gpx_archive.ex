defmodule Dawarich.Imports.GpxArchive do
  @moduledoc false
  alias Dawarich.Imports.GpxArchive.{Directory, Error, Stream}
  @supported ~w(.gpx .json .geojson .kml .kmz .csv .tcx .fit .rec)

  def inspect!(path, opts \\ []), do: prepare!(path, Keyword.put(opts, :inspect_only, true))

  def prepare!(path, opts \\ []) do
    File.open!(path, [:read, :binary, :raw], fn file ->
      if :file.pread(file, 0, 4) != {:ok, <<0x04034B50::little-32>>} do
        {:gpx, path}
      else
        archive = Directory.read!(file, opts)
        entries = Enum.reject(archive.entries, &String.ends_with?(&1.name, "/"))
        classify!(file, entries, archive.offset, opts)
      end
    end)
  rescue
    error in [MatchError, FunctionClauseError, ArgumentError] ->
      raise Error, message: "Malformed ZIP archive: #{inspect(error.__struct__)}"
  end

  def extract_entry!(path, entry, opts \\ []) do
    File.open!(path, [:read, :binary, :raw], fn file ->
      archive = Directory.read!(file, opts)

      unless entry in archive.entries and Directory.supported?(entry),
        do: raise(Error, message: "ZIP entry changed or has unsupported compression")

      extract!(file, entry, archive.offset, opts)
    end)
  end

  defp classify!(file, entries, central, opts) do
    cond do
      Enum.any?(entries, &(not Directory.supported?(&1))) ->
        {:legacy, :unsupported_zip}

      profile?(file, entries, central) ->
        {:legacy, :user_data_archive}

      length(entries) != 1 ->
        {:legacy, :multi_entry}

      Keyword.get(opts, :inspect_only, false) and
          String.downcase(Path.extname(hd(entries).name)) in @supported ->
        {:entry, hd(entries)}

      String.downcase(Path.extname(hd(entries).name)) == ".gpx" ->
        {:gpx, extract!(file, hd(entries), central, opts)}

      String.downcase(Path.extname(hd(entries).name)) in @supported ->
        {:legacy, :single_entry}

      true ->
        {:legacy, :multi_entry}
    end
  end

  defp profile?(file, entries, central) do
    manifest = Enum.find(entries, &(&1.name == "manifest.json"))
    data = Enum.find(entries, &(&1.name == "data.json"))
    v2?(file, manifest, central) or v1?(file, data, central)
  end

  defp v2?(_file, nil, _central), do: false

  defp v2?(file, entry, central) do
    if entry.size > 1_048_576 do
      false
    else
      case Jason.decode(Stream.prefix!(file, entry, central, 1_048_577)) do
        {:ok,
         %{
           "format_version" => 2,
           "dawarich_version" => _,
           "exported_at" => _,
           "counts" => %{},
           "files" => %{}
         }} ->
          true

        _ ->
          false
      end
    end
  end

  defp v1?(_file, nil, _central), do: false

  defp v1?(file, entry, central),
    do:
      Regex.match?(
        ~r/\A\s*\{\s*"counts"\s*:\s*\{.*?\}\s*,\s*"settings"\s*:/s,
        Stream.prefix!(file, entry, central, 65_536)
      )

  defp extract!(file, entry, central, opts) do
    limit =
      Keyword.get_lazy(opts, :max_bytes, fn ->
        System.get_env("ZIP_MAX_EXTRACTED_SIZE", "2147483648") |> String.to_integer()
      end)

    if not is_integer(limit) or limit < 0,
      do: raise(Error, message: "Invalid ZIP extracted byte budget")

    dir = Keyword.get(opts, :temp_dir, System.tmp_dir!())

    path =
      Path.join(
        dir,
        "unzipped-" <>
          Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false) <>
          Path.extname(entry.name)
      )

    owner = self()

    guard =
      spawn(fn ->
        monitor = Process.monitor(owner)

        receive do
          {:DOWN, ^monitor, :process, ^owner, _} -> File.rm(path)
          :keep -> Process.demonitor(monitor, [:flush])
        end
      end)

    try do
      File.open!(path, [:write, :exclusive, :binary, :raw], fn out ->
        File.chmod!(path, 0o600)
        Stream.consume!(file, entry, central, fn data -> :ok = :file.write(out, data) end, limit)
      end)

      if adopt = Keyword.get(opts, :on_verified), do: adopt.(path)
      send(guard, :keep)
      path
    rescue
      error ->
        File.rm(path)
        send(guard, :keep)
        reraise error, __STACKTRACE__
    catch
      kind, value ->
        File.rm(path)
        send(guard, :keep)
        :erlang.raise(kind, value, __STACKTRACE__)
    end
  end
end
