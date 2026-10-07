defmodule Dawarich.Storage.ContentType do
  @moduledoc false
  alias Dawarich.Storage.ImageVariant

  def identify(path, filename, declared) do
    bytes =
      File.open!(path, [:read, :binary], fn io ->
        case IO.binread(io, 4096) do
          :eof -> ""
          bytes when is_binary(bytes) -> bytes
          {:error, reason} -> raise File.Error, reason: reason, action: "read", path: "blob"
        end
      end)

    magic = signature(bytes) || ImageVariant.identify(path, nil)
    magic || declared_type(declared) || MIME.from_path(filename)
  end

  defp signature(bytes) do
    cond do
      String.starts_with?(bytes, ["%PDF-", <<239, 187, 191>> <> "%PDF-"]) ->
        "application/pdf"

      embedded_pdf?(bytes) ->
        "application/pdf"

      true ->
        nil
    end
  end

  defp embedded_pdf?(bytes) do
    case :binary.match(binary_part(bytes, 0, min(byte_size(bytes), 520)), ["%PDF-1.", "%PDF-2."]) do
      {offset, _} when offset in 1..512 -> true
      _ -> false
    end
  end

  defp declared_type(nil), do: nil

  defp declared_type(type) do
    type = type |> String.downcase() |> String.split(~r/[;,\s]/, parts: 2) |> hd()
    if type != "application/octet-stream" and String.contains?(type, "/"), do: type
  end
end
