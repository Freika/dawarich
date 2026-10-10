defmodule Dawarich.Storage.S3 do
  @moduledoc false

  @single_part_limit 8 * 1024 * 1024
  @max_parts 10_000
  @required ~w(AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION AWS_BUCKET)
  @virtual_hostable ~r/\A[a-z0-9][a-z0-9-]{2,62}\z/

  def config!(env) do
    [access_key_id, secret_access_key, region, bucket] = Enum.map(@required, &fetch!(env, &1))
    {scheme, host, port} = endpoint!(env["AWS_ENDPOINT_URL"] || env["AWS_ENDPOINT"], region)

    %{
      bucket: bucket,
      ex_aws: [
        access_key_id: access_key_id,
        secret_access_key: secret_access_key,
        region: region,
        http_client: Dawarich.Storage.HttpcClient,
        json_codec: Jason,
        scheme: scheme,
        host: host,
        port: port,
        virtual_host: bucket =~ @virtual_hostable and not ip?(host)
      ]
    }
  end

  def plan(size) when size < @single_part_limit, do: :single

  def plan(size),
    do: {:multipart, max(@single_part_limit, div(size + @max_parts - 1, @max_parts))}

  def put!(config, path, key, headers, checksum, size) do
    case plan(size) do
      :single ->
        request!(
          config,
          :put,
          key,
          nil,
          %{},
          File.read!(path),
          Map.put(headers, "content-md5", checksum)
        )

      {:multipart, part_size} ->
        multipart!(config, path, key, headers, part_size)
    end

    :ok
  end

  def delete(config, key) do
    case request(config, :delete, key, nil, %{}, "", %{}) do
      {:ok, %{status_code: status}} when status in 200..299 -> :ok
      {:ok, %{status_code: 404} = response} -> missing_delete(response)
      {:error, {:http_error, 404, response}} -> missing_delete(response)
      {:error, reason} -> {:error, reason}
      other -> {:error, {:delete_failed, status(other)}}
    end
  end

  defp missing_delete(%{body: body}) when is_binary(body) do
    if body =~ "<Code>NoSuchKey</Code>",
      do: :ok,
      else: {:error, :unconfirmed_missing_object}
  end

  defp missing_delete(_), do: {:error, :unconfirmed_missing_object}

  def download!(config, key, dest),
    do: File.open!(dest, [:write, :binary], &range!(config, key, &1, 0))

  def presigned_url!(config, method, key, query, headers, %DateTime{} = now, expires_in) do
    aws = ExAws.Config.new(:s3, config.ex_aws)

    {path, aws} =
      if aws[:virtual_host],
        do: {"/" <> key, Map.put(aws, :host, config.bucket <> "." <> aws.host)},
        else: {"/" <> config.bucket <> "/" <> key, aws}

    url =
      ExAws.Request.Url.build(%{path: path, params: %{}}, Map.put(aws, :normalize_path, false))

    at = now |> DateTime.to_naive() |> NaiveDateTime.to_erl()

    case ExAws.Auth.presigned_url(method, url, :s3, at, aws, expires_in, query, nil, headers) do
      {:ok, signed} -> signed
      {:error, _reason} -> raise "S3 presign failed"
    end
  end

  defp range!(config, key, io, from) do
    %{body: body, headers: headers} =
      request!(config, :get, key, nil, %{}, "", %{
        "range" => "bytes=#{from}-#{from + @single_part_limit - 1}"
      })

    IO.binwrite(io, body)

    total =
      headers
      |> header!("content-range")
      |> String.split("/")
      |> List.last()
      |> String.to_integer()

    if from + byte_size(body) < total,
      do: range!(config, key, io, from + byte_size(body)),
      else: :ok
  end

  defp multipart!(config, path, key, headers, part_size) do
    %{body: xml} = request!(config, :post, key, "uploads", %{}, "", headers)
    [_, upload_id] = Regex.run(~r|<UploadId>([^<]+)</UploadId>|, xml)

    try do
      parts =
        path
        |> File.stream!(part_size)
        |> Stream.with_index(1)
        |> Enum.map(fn {chunk, number} ->
          md5 = Base.encode64(:crypto.hash(:md5, chunk))
          params = %{"partNumber" => Integer.to_string(number), "uploadId" => upload_id}

          %{headers: response} =
            request!(config, :put, key, nil, params, chunk, %{"content-md5" => md5})

          {number, header!(response, "etag")}
        end)

      %{body: body} =
        request!(
          config,
          :post,
          key,
          nil,
          %{"uploadId" => upload_id},
          complete_xml(parts),
          %{"content-type" => "application/xml"}
        )

      if body =~ "<Error>", do: raise("CompleteMultipartUpload failed")
    catch
      kind, reason ->
        _ = request(config, :delete, key, nil, %{"uploadId" => upload_id}, "", %{})
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp complete_xml(parts) do
    body =
      Enum.map_join(parts, fn {n, etag} ->
        "<Part><PartNumber>#{n}</PartNumber><ETag>#{etag}</ETag></Part>"
      end)

    "<CompleteMultipartUpload>" <> body <> "</CompleteMultipartUpload>"
  end

  defp request!(config, method, key, resource, params, body, headers) do
    case request(config, method, key, resource, params, body, headers) do
      {:ok, %{status_code: status} = response} when status < 300 ->
        response

      other ->
        raise "S3 #{method} #{key} failed: #{inspect(status(other))}"
    end
  end

  defp request(config, method, key, resource, params, body, headers) do
    %ExAws.Operation.S3{
      http_method: method,
      bucket: config.bucket,
      path: key,
      resource: resource || "",
      params: params,
      body: body,
      headers: headers,
      parser: & &1
    }
    |> ExAws.request(config.ex_aws)
  end

  defp status({:ok, %{status_code: status}}), do: status
  defp status({:error, {:http_error, status, _}}), do: status
  defp status({:error, reason}), do: reason

  defp header!(headers, name) do
    Enum.find_value(headers, fn {key, value} -> String.downcase(key) == name && value end) ||
      raise "S3 response without #{name}"
  end

  defp fetch!(env, name) do
    case Map.get(env, name) do
      value when value in [nil, ""] -> raise ArgumentError, "STORAGE_BACKEND=s3 requires #{name}"
      value -> value
    end
  end

  defp endpoint!(url, region) when url in [nil, ""],
    do: {"https://", ExAws.Config.Defaults.host(:s3, region) || "s3.#{region}.amazonaws.com", 443}

  defp endpoint!(url, _region) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host, port: port}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        {scheme <> "://", host, port}

      _ ->
        raise ArgumentError, "invalid S3 endpoint"
    end
  end

  defp ip?(host), do: match?({:ok, _}, :inet.parse_address(String.to_charlist(host)))
end
