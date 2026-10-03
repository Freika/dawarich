defmodule Dawarich.Auth.Admission do
  @moduledoc false

  @special ~w(invitation_token pending_import_ticket dawarich_client)
  @fields ~w(authenticity_token user[email] user[password] user[remember_me] commit utf8 _method)

  def headers(headers) do
    names = Enum.map(headers, &elem(&1, 0))
    if length(names) == length(Enum.uniq(names)), do: :ok, else: {:handoff, :duplicate_headers}
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

  def form(raw, query) when is_binary(raw) and is_binary(query) do
    if query != "" or byte_size(raw) > 65_536 do
      {:handoff, :parameters}
    else
      raw
      |> String.split("&", trim: true)
      |> Enum.reduce_while({:ok, %{}}, &pair/2)
    end
  end

  defp present?(env, key), do: Dawarich.ReleaseMigration.ruby_strip(env[key] || "") != ""

  defp pair(segment, {:ok, acc}) do
    with [key, value] <- String.split(segment, "=", parts: 2),
         key <- URI.decode_www_form(key),
         value <- URI.decode_www_form(value),
         true <- not Regex.match?(~r/%(?![0-9a-fA-F]{2})/, segment),
         true <- String.valid?(key) and String.valid?(value),
         true <- key in @fields,
         true <- key != "user[remember_me]" or value in ["0", "1"] do
      case Map.fetch(acc, key) do
        :error ->
          {:cont, {:ok, Map.put(acc, key, value)}}

        {:ok, "0"} when key == "user[remember_me]" and value == "1" ->
          {:cont, {:ok, Map.put(acc, key, value)}}

        _ ->
          {:halt, {:handoff, :duplicate_parameters}}
      end
    else
      _ -> {:halt, {:handoff, :parameters}}
    end
  rescue
    ArgumentError -> {:halt, {:handoff, :parameters}}
  end
end
