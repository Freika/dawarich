defmodule Dawarich.EnhancedImport.SourceFile do
  @moduledoc false

  alias Dawarich.{RubyInteger, Storage}

  @blob """
  SELECT b.key, b.byte_size, b.checksum, b.service_name, b.filename FROM active_storage_attachments a
  JOIN active_storage_blobs b ON b.id = a.blob_id
  WHERE a.record_type = 'Import' AND a.record_id = $1 AND a.name = 'file'
  ORDER BY a.id DESC LIMIT 1
  """
  @no_content "Download completed but no content was received"
  @chunk 65_536
  @default_max 2 * 1024 * 1024 * 1024

  def fetch!(repo, import_id, storage, tmp) do
    case repo.query!(@blob, [import_id], log: false).rows do
      [] ->
        raise "undefined method 'download' for nil"

      [[_key, 0, _checksum, _service, _filename]] ->
        raise @no_content

      [[key, byte_size, checksum, service, filename]] ->
        path = Path.join(tmp, "source")

        blob = %{
          key: key,
          byte_size: byte_size,
          checksum: checksum,
          service_name: service,
          filename: filename
        }

        downloaded =
          Storage.Reader.download!(storage, blob, temp_dir: tmp, checksum_details: true)

        File.rename!(downloaded, path)
        if zip?(path), do: extract!(path, Path.join(tmp, "entry")), else: path
    end
  end

  defp zip?(path), do: File.open!(path, [:read, :binary], &IO.binread(&1, 4)) == "PK\x03\x04"

  defp extract!(path, dest) do
    entries =
      case :zip.list_dir(String.to_charlist(path)) do
        {:ok, entries} -> entries
        {:error, reason} -> raise "zip archive unreadable: #{inspect(reason)}"
      end

    case for(
           {:zip_file, _, info, _, offset, size} <- entries,
           elem(info, 2) == :regular,
           do: {offset, size}
         ) do
      [] ->
        raise ArgumentError, "zip has no entries"

      [{offset, size} | _] ->
        File.open!(path, [:read, :binary], &copy_entry!(&1, offset, size, dest, max_size()))
        dest
    end
  end

  defp copy_entry!(io, offset, size, dest, max) do
    {:ok, _} = :file.position(io, offset)

    <<0x04034B50::little-32, _::binary-4, method::little-16, _::binary-16, name::little-16,
      extra::little-16>> = IO.binread(io, 30)

    {:ok, _} = :file.position(io, {:cur, name + extra})
    File.open!(dest, [:write, :binary], &copy!(io, &1, method, size, max))
  end

  defp copy!(io, out, 0, size, max), do: chunks(io, size, 0, &write!(out, &1, &2, max))

  defp copy!(io, out, 8, size, max) do
    z = :zlib.open()
    :ok = :zlib.inflateInit(z, -15)

    try do
      chunks(io, size, 0, &inflate!(z, out, :zlib.safeInflate(z, &1), &2, max))
    after
      :zlib.close(z)
    end
  end

  defp copy!(_io, _out, method, _size, _max),
    do: raise("unsupported zip compression method #{method}")

  defp chunks(_io, 0, written, _fun), do: written

  defp chunks(io, left, written, fun) do
    chunk = IO.binread(io, min(left, @chunk))
    chunks(io, left - byte_size(chunk), fun.(chunk, written), fun)
  end

  defp inflate!(z, out, {:continue, data}, written, max),
    do: inflate!(z, out, :zlib.safeInflate(z, []), write!(out, data, written, max), max)

  defp inflate!(_z, out, {:finished, data}, written, max), do: write!(out, data, written, max)

  defp write!(out, data, written, max) do
    written = written + IO.iodata_length(data)
    if written > max, do: raise("entry exceeds #{max} bytes")
    IO.binwrite(out, data)
    written
  end

  defp max_size do
    case System.get_env("ZIP_MAX_EXTRACTED_SIZE") do
      nil -> @default_max
      value -> RubyInteger.to_i(value)
    end
  end
end
