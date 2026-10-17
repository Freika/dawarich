defmodule Dawarich.Storage.Reader do
  @moduledoc false
  alias Dawarich.{Imports.SecureFileDownloader, Storage}

  def download!(config, blob, opts \\ []) do
    case admit(config, blob) do
      :ok ->
        :ok

      {:legacy, :unsafe_storage_key} ->
        raise ArgumentError, "Invalid import storage key"

      {:legacy, _} ->
        raise ArgumentError, "Import blob service does not match configured storage service"
    end

    stream = source!(config, blob.key)
    SecureFileDownloader.download!(blob, stream, stream, opts)
  end

  def admit(config, blob) do
    cond do
      blob.service_name != Map.get(config, :stored_service, config.service) ->
        {:legacy, :storage_service_mismatch}

      config.service not in ["local", "s3"] ->
        {:legacy, :unsupported_storage_service}

      not valid_key?(config.service, blob.key) ->
        {:legacy, :unsafe_storage_key}

      true ->
        :ok
    end
  end

  defp valid_key?(service, key) when is_binary(key) do
    valid =
      String.valid?(key) and byte_size(key) <= 1024 and key != "" and
        not Regex.match?(~r/[\x00-\x1f\x7f]/, key)

    cond do
      not valid ->
        false

      service == "local" ->
        length(String.codepoints(key)) >= 4 and byte_size(key) <= 255 and
          not String.contains?(key, ["/", "\\"]) and key not in [".", ".."]

      true ->
        not String.contains?(key, ["?", "\\"]) and
          Enum.all?(String.split(key, "/"), &(&1 not in [".", ".."]))
    end
  end

  defp valid_key?(_, _), do: false

  defp source!(%{service: "local", root: root}, key) do
    characters = String.codepoints(key)
    first = characters |> Enum.take(2) |> Enum.join()
    second = characters |> Enum.drop(2) |> Enum.take(2) |> Enum.join()
    path = Path.join([root, first, second, key])
    fn sink -> path |> File.stream!(1_048_576) |> Enum.each(sink) end
  end

  defp source!(%{service: "s3"} = config, key) do
    fn sink -> Storage.HttpDownload.stream!(signed_url!(config, key), sink) end
  end

  defp source!(_, _), do: raise(ArgumentError, "Unsupported import blob service")

  defp signed_url!(config, key) do
    aws = ExAws.Config.new(:s3, config.ex_aws)

    {path, aws} =
      if aws[:virtual_host] do
        {"/" <> key, Map.put(aws, :host, config.bucket <> "." <> aws.host)}
      else
        {"/" <> config.bucket <> "/" <> key, aws}
      end

    url =
      ExAws.Request.Url.build(%{path: path, params: %{}}, Map.put(aws, :normalize_path, false))

    case ExAws.Auth.presigned_url(:get, url, :s3, :calendar.universal_time(), aws, 300) do
      {:ok, url} -> url
      {:error, _} -> raise "Import storage signing failed"
    end
  end
end
