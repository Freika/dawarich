defmodule Dawarich.Auth.Admission do
  @moduledoc false

  @special ~w(invitation_token pending_import_ticket dawarich_client)
  @fields ~w(authenticity_token user[email] user[password] user[remember_me] commit utf8 _method)

  def headers(headers) do
    names = Enum.map(headers, &elem(&1, 0))
    if length(names) == length(Enum.uniq(names)), do: :ok, else: {:handoff, :duplicate_headers}
  end

  def context(session, %Plug.Conn{} = conn, oidc_enabled, self_hosted) do
    with :ok <- headers(conn.req_headers) do
      DawarichWeb.RailsRemoteIp.ip(conn)

      headers =
        Enum.reject(conn.req_headers, fn {key, _} ->
          key in ~w(x-forwarded-for client-ip forwarded)
        end)

      context(session, headers, oidc_enabled, self_hosted)
    end
  rescue
    DawarichWeb.RailsRemoteIp.IpSpoofAttackError -> {:handoff, :client_ip}
  end

  def context(session, headers, oidc_enabled, self_hosted) do
    cond do
      headers(headers) != :ok ->
        {:handoff, :duplicate_headers}

      not self_hosted ->
        {:handoff, :cloud}

      oidc_enabled ->
        {:handoff, :oidc}

      Enum.any?(@special, &Map.has_key?(session, &1)) ->
        {:handoff, :special_session}

      Enum.any?(headers, fn {key, _} -> key == "x-http-method-override" end) ->
        {:handoff, :method_override}

      Enum.any?(headers, fn {key, _} -> key in ["x-forwarded-for", "client-ip", "forwarded"] end) ->
        {:handoff, :client_ip}

      Enum.any?(headers, fn {key, _} -> key == "x-dawarich-client" end) ->
        {:handoff, :mobile}

      true ->
        :ok
    end
  end

  def oidc?(env \\ System.get_env()) do
    (present?(env, "GOOGLE_OAUTH_CLIENT_ID") and present?(env, "GOOGLE_OAUTH_CLIENT_SECRET")) or
      (present?(env, "OIDC_CLIENT_ID") and
         (present?(env, "OIDC_CLIENT_SECRET") or
            String.downcase(Dawarich.ReleaseMigration.ruby_strip(env["OIDC_PKCE_ENABLED"] || "")) ==
              "true"))
  end

  def form(raw, query), do: form(raw, query, @fields)

  def form(raw, query, fields) when is_binary(raw) and is_binary(query) and is_list(fields) do
    if query == "" do
      pairs = if fields == @fields, do: %{"user[remember_me]" => ["0", "1"]}, else: %{}
      form(raw, query, fields, checkbox_pairs: pairs)
    else
      {:handoff, :parameters}
    end
  end

  def form(raw, query, fields, opts)
      when is_binary(raw) and is_binary(query) and is_list(fields) do
    query_fields = Keyword.get(opts, :query_fields, %{})
    pairs = Keyword.get(opts, :checkbox_pairs, %{})

    if byte_size(raw) > 65_536 or byte_size(query) > 65_536 do
      {:handoff, :parameters}
    else
      with {:ok, body} <- decode(raw, fields, pairs),
           {:ok, decoded_query} <- decode(query, Map.keys(query_fields), %{}),
           true <- query == "" or map_size(decoded_query) > 0,
           true <- Enum.all?(decoded_query, fn {key, value} -> value in query_fields[key] end),
           true <- Enum.all?(Map.keys(decoded_query), &(not Map.has_key?(body, &1))) do
        {:ok, Map.merge(body, decoded_query)}
      else
        {:handoff, _} = error -> error
        _ -> {:handoff, :parameters}
      end
    end
  end

  defp decode(raw, fields, pairs) do
    raw
    |> String.split("&", trim: true)
    |> Enum.reduce_while({:ok, %{}}, &pair(&1, &2, fields, pairs))
  end

  defp present?(env, key), do: Dawarich.ReleaseMigration.ruby_strip(env[key] || "") != ""

  defp pair(segment, {:ok, acc}, fields, pairs) do
    with [key, value] <- String.split(segment, "=", parts: 2),
         key <- URI.decode_www_form(key),
         value <- URI.decode_www_form(value),
         true <- not Regex.match?(~r/%(?![0-9a-fA-F]{2})/, segment),
         true <- String.valid?(key) and String.valid?(value),
         true <- key in fields,
         true <- key != "user[remember_me]" or value in ["0", "1"] do
      case Map.fetch(acc, key) do
        :error ->
          {:cont, {:ok, Map.put(acc, key, value)}}

        {:ok, previous} ->
          if Map.get(pairs, key) == [previous, value] and previous != value,
            do: {:cont, {:ok, Map.put(acc, key, value)}},
            else: {:halt, {:handoff, :duplicate_parameters}}
      end
    else
      _ -> {:halt, {:handoff, :parameters}}
    end
  rescue
    ArgumentError -> {:halt, {:handoff, :parameters}}
  end
end
