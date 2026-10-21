defmodule Dawarich.Cloud.EndpointURL do
  @moduledoc false
  @pooled ["transaction", "statement", :transaction, :statement]

  def origin?(url) do
    with {:ok, uri} <- uri(url),
         true <- uri.scheme == "https" and uri.port in 1..65_535,
         {:ok, _} <- canonical_host(uri.host, false),
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
         true <- uri.scheme in ["postgres", "postgresql"],
         {:ok, host} <- canonical_host(uri.host, true),
         true <- is_binary(uri.path) and String.starts_with?(uri.path, "/"),
         db <- uri.path |> String.slice(1..-1//1) |> URI.decode(),
         true <- db != "" and not Regex.match?(~r/[\s\/\x{00a0}\x00-\x1f]/u, db),
         port <- uri.port || 5432,
         true <- port in 1..65_535,
         query <- URI.query_decoder(uri.query || "") |> Enum.to_list() do
      {:ok, %{host: host, port: port, query: query}}
    else
      _ -> :error
    end
  end

  defp canonical_host(host, ipv6) when is_binary(host) do
    host = host |> String.downcase() |> String.replace_suffix(".", "")

    host =
      if String.starts_with?(host, "[") and String.ends_with?(host, "]") and
           String.contains?(host, ":"),
         do: String.slice(host, 1..-2//1),
         else: host

    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, address} when tuple_size(address) == 4 ->
        if host == to_string(:inet.ntoa(address)), do: {:ok, host}, else: :error

      {:ok, address} when ipv6 ->
        if Regex.match?(~r/\A[0-9a-f:.]+\z/, host),
          do: {:ok, address |> canonical_address() |> :inet.ntoa() |> to_string()},
          else: :error

      {:error, _} ->
        numeric = Regex.match?(~r/\A(?:0x[0-9a-f]+|[0-9]+)(?:\.(?:0x[0-9a-f]+|[0-9]+))*\z/, host)

        valid =
          not numeric and byte_size(host) <= 253 and
            Enum.all?(String.split(host, "."), fn label ->
              byte_size(label) in 1..63 and
                Regex.match?(~r/\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\z/, label)
            end)

        if valid, do: {:ok, host}, else: :error

      _ ->
        :error
    end
  end

  defp canonical_host(_, _), do: :error

  defp canonical_address({0, 0, 0, 0, 0, prefix, high, low})
       when prefix == 65_535 or (prefix == 0 and (high > 0 or low > 1)) do
    {div(high, 256), rem(high, 256), div(low, 256), rem(low, 256)}
  end

  defp canonical_address(address), do: address

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
        {:ok, host} = canonical_host(host, true)
        true = port in 1..65_535
        %{host: host, port: port, query: []}
      end)

    endpoints = urls ++ configured

    not (declared and endpoints == []) and
      Enum.all?(endpoints, fn endpoint ->
        not (declared or pooled?(endpoint)) or identity(endpoint) != identity(session)
      end)
  end

  defp identity(endpoint), do: {endpoint.host, endpoint.port}
end
