defmodule DawarichWeb.StandaloneAuth do
  @moduledoc false
  import Plug.Conn
  alias DawarichWeb.{AuthAccount, AuthAccountLink, AuthProvider, AuthRecovery, AuthRegistration}

  def call(conn) do
    cond do
      conn.method == "POST" and conn.request_path == "/users" ->
        registration_post(conn)

      AuthRegistration.Http.route?(conn) ->
        AuthRegistration.Http.call(conn, options(:registration))

      AuthRecovery.Http.route?(conn) ->
        AuthRecovery.Http.call(conn, options(:recovery))

      AuthProvider.Http.route?(conn) ->
        AuthProvider.Http.call(conn, options(:provider_auth))

      AuthAccountLink.Http.closure_route?(conn) ->
        AuthAccountLink.Http.call(conn, Keyword.put(options(:account_link), :closure, true))

      true ->
        conn
    end
  end

  defp registration_post(conn) do
    case body(conn) do
      {:ok, raw, conn} ->
        conn = put_private(conn, :dawarich_raw_body, raw)

        overrides =
          raw
          |> String.split("&", trim: true)
          |> Enum.map(&String.split(&1, "=", parts: 2))
          |> Enum.filter(fn pair -> URI.decode_www_form(hd(pair)) == "_method" end)

        case overrides do
          [] ->
            AuthRegistration.Http.call(conn, options(:registration))

          [[_, method]] when method in ["patch", "put"] ->
            AuthAccount.Http.call(conn, options(:account))

          _ ->
            reject(conn)
        end

      _ ->
        reject(conn)
    end
  rescue
    ArgumentError -> reject(conn)
  end

  defp body(%{private: %{dawarich_raw_body: raw}} = conn) when byte_size(raw) <= 65_536,
    do: {:ok, raw, conn}

  defp body(conn), do: read_body(conn, length: 65_536, read_length: 65_536)

  defp options(flow) do
    context = Application.get_env(:dawarich, context_key(flow), %{}) || %{}

    context =
      if flow in [:registration, :recovery],
        do: Dawarich.Auth.RegistrationPolicy.context(context),
        else: context

    context =
      if flow == :recovery,
        do: Map.put_new(context, :enqueue, &Dawarich.Auth.Recovery.MailWorker.enqueue/1),
        else: context

    [enabled: true, native: true, context: context, fallback: &reject/1]
  end

  defp context_key(:registration), do: :registration_context
  defp context_key(:recovery), do: :recovery_context
  defp context_key(:provider_auth), do: :provider_auth_context
  defp context_key(:account_link), do: :account_link_context
  defp context_key(:account), do: :account_context
  defp reject(conn), do: DawarichWeb.StandaloneError.respond(conn, "auth_envelope", 422)
end
