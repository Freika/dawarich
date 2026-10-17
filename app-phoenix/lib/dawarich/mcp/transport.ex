defmodule Dawarich.Mcp.Transport do
  @moduledoc false
  alias Dawarich.{Accounts, AppVersion, Entitlements}
  @versions ~w(2026-07-28 2025-11-25 2025-06-18 2025-03-26 2024-11-05)
  @instructions "Use these read-only tools to inspect the authenticated user's own location history."

  def authorize(headers, _query) do
    with [_, key] <- Regex.run(~r/\ABearer\s+(\S+)\z/i, header(headers, "authorization") || ""),
         %{} = user <- Accounts.by_api_key(key) do
      if user.status == 3,
        do: {:error, 402},
        else: {:ok, %{user | timezone: user.timezone || "Etc/UTC"}}
    else
      _ -> {:error, 401}
    end
  rescue
    _ -> {:error, 500}
  end

  def request(method, headers, raw, user) do
    cond do
      not Entitlements.full_access?(
        user,
        System.get_env("SELF_HOSTED") != "false",
        DateTime.utc_now()
      ) ->
        {403, %{"error" => "pro_plan_required"}}

      method == "GET" ->
        error(405, nil, -32600, "Method not allowed")

      method == "DELETE" ->
        case protocol(headers) do
          :ok -> {200, %{"success" => true}}
          reply -> reply
        end

      method != "POST" ->
        error(405, nil, -32600, "Method not allowed")

      byte_size(raw) > 4 * 1024 * 1024 ->
        error(413, nil, -32600, "Payload too large: request body exceeds 4194304 bytes")

      not accepts?(headers) ->
        error(406, nil, -32600, "Not Acceptable: Accept header must include application/json")

      media_type(header(headers, "content-type")) != "application/json" ->
        error(415, nil, -32600, "Unsupported Media Type: Content-Type must be application/json")

      true ->
        parse(raw, headers, user)
    end
  rescue
    _ -> error(500, nil, -32603, "Internal server error")
  end

  def error(status, id, code, message),
    do:
      {status,
       %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message}}}

  defp parse(raw, headers, user) do
    case Jason.decode(raw) do
      {:ok, %{} = rpc} ->
        if rpc["method"] in ["initialize", "server/discover"] do
          rpc(rpc, user)
        else
          case protocol(headers) do
            :ok -> rpc(rpc, user)
            reply -> reply
          end
        end

      {:ok, _} ->
        error(400, nil, -32600, "Invalid Request: JSON-RPC body must be a single request object")

      _ ->
        error(400, nil, -32700, "Parse error: Invalid JSON")
    end
  end

  defp rpc(%{"method" => method} = rpc, user) do
    id = rpc["id"]
    params = rpc["params"] || %{}

    cond do
      is_nil(id) ->
        {202, nil}

      rpc["jsonrpc"] != "2.0" ->
        error(200, id, -32600, "Invalid Request")

      method == "initialize" ->
        initialize(id, params)

      method == "ping" ->
        result(id, %{})

      method == "tools/list" ->
        result(id, %{"tools" => apply(Dawarich.Mcp.Tools, :list, [])})

      method == "tools/call" ->
        case apply(Dawarich.Mcp.Tools, :call, [user, params]) do
          {:ok, payload} -> result(id, payload)
          {:rpc_error, code, message} -> error(200, id, code, message)
        end

      true ->
        error(200, id, -32601, "Method not found")
    end
  end

  defp rpc(_rpc, _user), do: error(200, nil, -32600, "Invalid Request")

  defp initialize(id, params) do
    if is_map(params) and is_binary(params["protocolVersion"]) and is_map(params["capabilities"]) and
         is_map(params["clientInfo"]) and params["clientInfo"]["name"] != nil and
         params["clientInfo"]["version"] != nil do
      version =
        if params["protocolVersion"] in tl(@versions),
          do: params["protocolVersion"],
          else: "2025-11-25"

      info = %{"name" => "dawarich", "title" => "Dawarich", "version" => AppVersion.current()}
      info = if version <= "2025-03-26", do: Map.delete(info, "title"), else: info

      body = %{
        "protocolVersion" => version,
        "capabilities" => %{
          "tools" => %{"listChanged" => true},
          "prompts" => %{"listChanged" => true},
          "resources" => %{"listChanged" => true},
          "logging" => %{}
        },
        "serverInfo" => info
      }

      body =
        if version == "2024-11-05", do: body, else: Map.put(body, "instructions", @instructions)

      result(id, body)
    else
      error(200, id, -32602, "Missing or invalid initialize parameters")
    end
  end

  defp result(id, value), do: {200, %{"jsonrpc" => "2.0", "id" => id, "result" => value}}

  defp protocol(headers) do
    version = header(headers, "mcp-protocol-version")

    if is_nil(version) or version in @versions,
      do: :ok,
      else:
        error(
          400,
          nil,
          -32600,
          "Bad Request: Unsupported protocol version: #{version}. Supported versions: #{Enum.join(@versions, ", ")}"
        )
  end

  defp accepts?(headers),
    do:
      String.split(header(headers, "accept") || "", ",")
      |> Enum.any?(&(media_type(&1) in ["application/json", "*/*"]))

  defp media_type(nil), do: ""

  defp media_type(value),
    do: value |> String.split(";") |> hd() |> String.trim() |> String.downcase()

  defp header(headers, key) do
    case List.keyfind(headers, key, 0) do
      {_, value} -> value
      _ -> nil
    end
  end
end
