defmodule Dawarich.Storage.ImportServices do
  @moduledoc """
  Resolves explicitly declared Rails storage services for native imports.

  The reader accepts the project's bounded storage.yml dialect, not arbitrary
  Ruby ERB or YAML objects. Unsupported configurations remain Rails-owned.
  """
  alias Dawarich.Storage.{ImportServiceFile, Reader, S3}

  def configured!(env, rails_root) do
    path = Path.join(rails_root, "config/storage.yml")

    case File.read(path) do
      {:ok, text} ->
        text
        |> ImportServiceFile.parse(env, rails_root)
        |> Enum.flat_map(fn {name, values} ->
          case config(values, rails_root) do
            nil -> []
            config -> [{name, Map.put(config, :stored_service, name)}]
          end
        end)
        |> Map.new()

      {:error, _} ->
        %{}
    end
  end

  def resolve(services, %{service_name: name} = blob) do
    case Map.fetch(services, name) do
      {:ok, config} ->
        case Reader.admit(config, blob) do
          :ok -> {:ok, config}
          legacy -> legacy
        end

      :error ->
        {:legacy, :unconfigured_storage_service}
    end
  end

  defp config(%{"service" => "Disk", "root" => root} = values, _) do
    if supported?(values, ~w(service root public)) and is_binary(root) and
         Path.type(root) == :absolute,
       do: %{service: "local", root: root}
  end

  defp config(%{"service" => "S3"} = values, rails_root) do
    fields =
      ~w(service access_key_id secret_access_key region bucket endpoint force_path_style request_checksum_calculation response_checksum_validation public)

    if supported?(values, fields) and endpoint?(values["endpoint"]) and bucket?(values["bucket"]) and
         values["force_path_style"] in [nil, "true", "false"] do
      env = %{
        "AWS_ACCESS_KEY_ID" => values["access_key_id"],
        "AWS_SECRET_ACCESS_KEY" => values["secret_access_key"],
        "AWS_REGION" => values["region"],
        "AWS_BUCKET" => values["bucket"],
        "AWS_ENDPOINT_URL" => values["endpoint"]
      }

      aws = S3.config!(env)

      aws =
        if values["force_path_style"] == "true",
          do: update_in(aws.ex_aws, &Keyword.put(&1, :virtual_host, false)),
          else: aws

      Map.merge(%{service: "s3", root: Path.join(rails_root, "storage")}, aws)
    end
  rescue
    ArgumentError -> nil
  end

  defp config(_, _), do: nil

  defp supported?(values, fields),
    do: Enum.all?(values, fn {key, value} -> key in fields and is_binary(value) end)

  defp bucket?(value) when is_binary(value),
    do: Regex.match?(~r/\A[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]\z/, value)

  defp bucket?(_), do: false

  defp endpoint?(nil), do: true
  defp endpoint?(""), do: true

  defp endpoint?(value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host, userinfo: nil, query: nil, fragment: nil, path: path}
      when scheme in ["http", "https"] and is_binary(host) and host != "" and
             path in [nil, "", "/"] ->
        true

      _ ->
        false
    end
  end
end
