defmodule Dawarich.UserData.Export.RawArchives do
  @moduledoc false
  alias Dawarich.UserData.Export.{Serializer, Files}
  alias Dawarich.RawData.ArchiveFormat

  def write(repo, user, dir, context) do
    table = "points_raw_data_archives"
    columns = Serializer.columns(repo, table, [])
    path = Path.join(dir, "raw_data_archives.jsonl")

    count =
      File.open!(path, [:write, :binary], fn io ->
        Serializer.pages(repo, user, table, columns, context.zone)
        |> Enum.reduce(0, fn [id | values], count ->
          pairs =
            Enum.zip_with(columns, values, fn {name, type}, value ->
              {name, Serializer.value(table, name, type, value)}
            end)

          pairs =
            case Files.blobs(repo, "Points::RawDataArchive", id) do
              [] -> pairs
              [blob] -> attachment(pairs, blob, dir, context)
            end

          :ok = IO.binwrite(io, [Serializer.encode(%Jason.OrderedObject{values: pairs}), "\n"])
          count + 1
        end)
      end)

    [%{name: "raw_data_archives.jsonl", path: path, count: count}]
  end

  defp attachment(pairs, blob, dir, context) do
    row = Map.new(pairs)

    name =
      "raw_data_archive_#{row["year"]}_#{row["month"] |> Integer.to_string() |> String.pad_leading(2, "0")}_#{row["chunk_number"]}.jsonl.gz"

    path = Path.join([dir, "files", name])

    try do
      content = Files.raw!(blob, context)
      metadata = row["metadata"] || %Jason.OrderedObject{values: []}
      key = Map.get_lazy(context, :archive_key, &ArchiveFormat.key/0)

      gzip =
        case ArchiveFormat.decode(content, Map.new(metadata.values), key) do
          {:ok, gzip} -> gzip
          {:error, _} -> raise decrypt_message(content)
        end

      File.write!(path, gzip)

      values =
        metadata.values
        |> List.keydelete("encryption", 0)
        |> List.keystore("format_version", 0, {"format_version", 1})
        |> List.keystore("content_checksum", 0, {"content_checksum", ArchiveFormat.sha256(gzip)})

      pairs
      |> List.keystore("metadata", 0, {"metadata", %Jason.OrderedObject{values: values}})
      |> Kernel.++([
        {"file_name", name},
        {"original_filename", name},
        {"content_type", "application/gzip"}
      ])
    rescue
      error ->
        File.rm(path)
        pairs ++ [{"file_error", "Failed to export archive file: " <> Files.message(error)}]
    end
  end

  defp decrypt_message(content) do
    if length(String.split(content, "--")) != 3, do: "missing separator", else: ""
  end
end
