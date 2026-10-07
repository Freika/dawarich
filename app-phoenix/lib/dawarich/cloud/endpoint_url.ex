defmodule Dawarich.Cloud.EndpointURL do
  @moduledoc false
  @pooled ["transaction", "statement", :transaction, :statement]

  def origin?(url) do
    with {:ok, uri} <- uri(url),
         true <- uri.scheme == "https" and uri.port in 1..65_535,
         true <- host?(uri.host, false),
         true <- uri.userinfo == nil and uri.path in [nil, ""] and uri.query == nil,
         do: true,
         else: (_ -> false)
  end

  def session?(url, env, config \\ []) do
    with {:ok, parsed} <- database(url),
         false <- pooled?(parsed),
         true <- session_query?(parsed.query),
         true <- distinct?(parsed, env, config),
         do: true,
         else: (_ -> false)
  rescue
    _ -> false
  end

  defp uri(url) when is_binary(url) do
    if String.valid?(url) and not Regex.match?(~r/[\s\x{00a0}]/u, url) and
         not Regex.match?(~r/%(?![0-9a-fA-F]{2})/, url) do
      case URI.new(url) do
        {:ok, %URI{fragment: nil} = uri} -> {:ok, uri}
        _ -> :error
      end
    else
      :error
    end
  end

  defp uri(_), do: :error

  defp database(url) do
    with {:ok, uri} <- uri(url),
         true <- uri.scheme in ["postgres", "postgresql"] and host?(uri.host, true),
         true <- is_binary(uri.path) and String.starts_with?(uri.path, "/"),
         db <- uri.path |> String.slice(1..-1//1) |> URI.decode(),
         true <- db != "" and not Regex.match?(~r/[\s\/\x{00a0}\x00-\x1f]/u, db),
         port <- uri.port || 5432,
         true <- port in 1..65_535,
         query <- URI.query_decoder(uri.query || "") |> Enum.to_list() do
      {:ok, %{host: normalize_host(uri.host), port: port, query: query}}
    else
      _ -> :error
    end
  end

  defp host?(host, ipv6) when is_binary(host) do
    normalized = host |> String.downcase() |> String.replace_suffix(".", "")

    cond do
      String.contains?(normalized, ":") ->
        ipv6 and match?({:ok, _}, :inet.parse_ipv6_address(String.to_charlist(normalized)))

      Regex.match?(~r/\A(?:0x[0-9a-f]+|[0-9]+)(?:\.(?:0x[0-9a-f]+|[0-9]+))*\z/, normalized) ->
        String.split(normalized, ".") |> length() == 4 and
          match?({:ok, _}, :inet.parse_ipv4strict_address(String.to_charlist(normalized)))

      true ->
        byte_size(normalized) <= 253 and
          Enum.all?(String.split(normalized, "."), fn label ->
            byte_size(label) in 1..63 and
              Regex.match?(~r/\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\z/, label)
          end)
    end
  end

  defp host?(_, _), do: false

  defp normalize_host(host) do
    host = host |> String.downcase() |> String.replace_suffix(".", "")

    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, address} -> address |> :inet.ntoa() |> to_string()
      _ -> host
    end
  end

  defp pooled?(endpoint) do
    endpoint.port == 6432 or String.contains?(endpoint.host, "pgbouncer") or
      Enum.any?(endpoint.query, fn {key, value} ->
        String.downcase(key) == "pgbouncer" or
          (key in ["pool_mode", "pooling_mode"] and value in @pooled)
      end)
  end

  defp session_query?(pairs) do
    keys = Enum.map(pairs, &elem(&1, 0))

    length(keys) == length(Enum.uniq(keys)) and
      Enum.count(keys, &(&1 in ["pool_mode", "pooling_mode"])) <= 1 and
      Enum.all?(pairs, fn
        {"sslmode", value} -> value in ~w(disable require verify-ca verify-full)
        {key, "session"} when key in ["pool_mode", "pooling_mode"] -> true
        _ -> false
      end)
  end

  defp distinct?(session, env, config) do
    declared =
      env["DATABASE_POOLING_MODE"] in @pooled or
        config[:pool_mode] in @pooled or config[:pooling_mode] in @pooled

    urls =
      [env["DATABASE_URL"], config[:url]]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.map(fn url ->
        {:ok, endpoint} = database(url)
        endpoint
      end)

    configured =
      cond do
        config[:endpoints] -> config[:endpoints]
        config[:hostname] -> [{config[:hostname], config[:port] || 5432}]
        true -> []
      end
      |> Enum.map(fn {host, port} ->
        true = host?(host, true) and port in 1..65_535
        %{host: normalize_host(host), port: port, query: []}
      end)

    endpoints = urls ++ configured

    not (declared and endpoints == []) and
      Enum.all?(endpoints, fn endpoint ->
        not (declared or pooled?(endpoint)) or identity(endpoint) != identity(session)
      end)
  end

  defp identity(endpoint), do: {endpoint.host, endpoint.port}
end
