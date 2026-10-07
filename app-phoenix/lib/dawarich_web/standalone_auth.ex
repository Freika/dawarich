defmodule DawarichWeb.StandaloneAuth do
  @moduledoc false
  import Plug.Conn

  alias DawarichWeb.{
    AuthAccount,
    AuthAccountLink,
    AuthApple,
    AuthHandler,
    AuthMobile,
    AuthOtp,
    AuthProvider,
    AuthRecovery,
    AuthRegistration
  }

  @browser [
    AuthAccount.Http,
    AuthAccount.Destroy,
    AuthAccountLink.Http,
    AuthApple.Http,
    AuthHandler,
    AuthOtp.Http,
    AuthProvider.Http,
    AuthRecovery.Http,
    AuthRegistration.Http
  ]

  def call(conn) do
    conn = apple_transport(conn)

    cond do
      conn.halted -> conn
      browser?(conn) and ambiguous_cookies?(conn) -> refuse_cookie(conn)
      true -> dispatch(conn)
    end
  end

  defp apple_transport(conn) do
    path = String.replace(conn.request_path, ~r/\.(html|json)\z/, "")

    if path in ["/users/auth/apple", "/users/auth/apple/callback"] do
      conn = transport(conn)
      conn = if conn.method == "HEAD", do: put_private(conn, :dawarich_method, "HEAD"), else: conn

      %{
        conn
        | request_path: path,
          path_info: String.split(path, "/", trim: true),
          method: if(conn.method == "HEAD", do: "GET", else: conn.method)
      }
    else
      conn
    end
  end

  defp browser?(conn),
    do:
      AuthMobile.Http.route?(conn) or AuthAccountLink.Http.closure_route?(conn) or
        Enum.any?(@browser, & &1.route?(conn))

  defp ambiguous_cookies?(conn) do
    cookies = get_req_header(conn, "cookie")
    names = ~w(_dawarich_session apple_oauth_state apple_oauth_nonce apple_pending_import_ticket)

    length(cookies) > 1 or
      Enum.any?(names, fn name ->
        length(Regex.scan(Regex.compile!("(?:\\A|;)\\s*" <> name <> "="), Enum.join(cookies))) > 1
      end)
  end

  defp dispatch(conn) do
    cond do
      conn.method == "POST" and conn.request_path == "/users" ->
        registration_post(conn)

      AuthAccount.Destroy.route?(conn) ->
        AuthAccount.Destroy.call(conn, options(:account_destroy))

      AuthAccount.Http.route?(conn) ->
        AuthAccount.Http.call(conn, options(:account))

      AuthApple.Http.route?(conn) ->
        AuthApple.Http.call(conn, options(:apple_auth))

      AuthMobile.Http.route?(conn) ->
        AuthMobile.Http.call(conn, options(:api_auth))

      AuthMobile.Success.route?(conn) ->
        admitted_success(conn)

      conn.method == "POST" and conn.request_path == "/api/v1/subscriptions/callback" ->
        DawarichWeb.Api.SubscriptionsController.call(conn, options(:subscription))

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
            conn
            |> put_private(:dawarich_rate_limit_method, String.upcase(method))
            |> AuthAccount.Http.call(options(:account))

          [[_, "delete"]] ->
            AuthAccount.Destroy.call(conn, options(:account_destroy))

          _ ->
            reject(conn)
        end

      _ ->
        reject(conn)
    end
  rescue
    ArgumentError -> reject(conn)
  end

  defp transport(conn),
    do: conn |> DawarichWeb.HostAuthorization.call([]) |> DawarichWeb.ForceSSL.call([])

  defp refuse_cookie(conn) do
    conn = transport(conn)
    if conn.halted, do: conn, else: reject(conn)
  end

  defp admitted_success(conn) do
    conn = transport(conn)
    conn = if conn.halted, do: conn, else: DawarichWeb.RateLimit.call(conn, [])
    if conn.halted, do: conn, else: AuthMobile.Success.call(conn, options(:api_auth))
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

    context =
      Map.put_new(context, :mobile_redirect, fn user, client ->
        Dawarich.Auth.Mobile.Handoff.redirect(user, client, context)
      end)

    [enabled: true, native: true, context: context, fallback: &reject/1]
  end

  defp context_key(:registration), do: :registration_context
  defp context_key(:recovery), do: :recovery_context
  defp context_key(:provider_auth), do: :provider_auth_context
  defp context_key(:account_link), do: :account_link_context
  defp context_key(:apple_auth), do: :apple_auth_context
  defp context_key(:api_auth), do: :api_auth_context
  defp context_key(:subscription), do: :subscription_context
  defp context_key(:account_destroy), do: :account_destroy_context
  defp context_key(:account), do: :account_context
  defp reject(conn), do: DawarichWeb.StandaloneError.respond(conn, "auth_envelope", 422)
end
