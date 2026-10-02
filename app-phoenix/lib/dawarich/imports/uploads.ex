defmodule Dawarich.Imports.Uploads do
  @moduledoc false
  alias Dawarich.Imports.RailsBlobReference

  @columns [:id, :key, :filename, :content_type, :metadata, :service_name, :byte_size, :checksum]
  @select "id,key,filename,content_type,metadata,service_name,byte_size,checksum"

  def fetch(repo, token) do
    with {:ok, id} <- RailsBlobReference.verify(token) do
      case repo.query!("SELECT #{@select} FROM public.active_storage_blobs WHERE id=$1", [id],
             log: false
           ).rows do
        [row] ->
          blob = Map.new(Enum.zip(@columns, row))
          {:ok, %{blob | metadata: metadata(blob.metadata)}}

        _ ->
          {:error, :not_found}
      end
    end
  end

  defp metadata(value) when is_map(value), do: value

  defp metadata(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, %{} = map} -> map
      _ -> %{}
    end
  end

  defp metadata(_), do: %{}
end
