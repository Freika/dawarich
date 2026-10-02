defmodule Dawarich.Imports.Download.Names do
  @moduledoc false
  @supported ~w(.gpx .json .geojson .kml .kmz .csv .tcx .fit .rec)

  def original(blob) do
    Map.get(blob.metadata, "dawarich_original_filename") || legacy(blob.filename)
  end

  def wrapped?(blob) do
    case Map.fetch(blob.metadata, "dawarich_client_wrapped") do
      {:ok, marker} -> marker not in [nil, false]
      :error -> legacy(blob.filename) != nil
    end
  end

  def ready?(%{source: nil}), do: false

  def ready?(%{source: source, prepared: prepared}) do
    not wrapped?(source) or
      (prepared != nil and
         (prepared.id == source.id or
            prepared.metadata["dawarich_download_source_blob_id"] == source.id))
  end

  def filename(%{name: name, source: source, prepared: prepared}) do
    if wrapped?(source) do
      if prepared.id == source.id do
        if String.ends_with?(name, ".zip"), do: name, else: name <> ".zip"
      else
        original = original(source)

        suffix =
          if original && String.starts_with?(name, original),
            do: String.replace_prefix(name, original, ""),
            else: name

        cond do
          name == source.filename ->
            original

          original && Regex.match?(~r/\A_\d{8}_\d{6}\.zip\z/, suffix) ->
            ext = Path.extname(original)
            String.trim_trailing(original, ext) <> String.trim_trailing(suffix, ".zip") <> ext

          true ->
            name
        end
      end
    else
      name
    end
  end

  defp legacy(filename) do
    if String.ends_with?(filename, ".zip") do
      inner = String.trim_trailing(filename, ".zip")
      if String.downcase(Path.extname(inner)) in @supported, do: inner
    end
  end
end
