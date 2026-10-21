defmodule DawarichWeb.AuthProvider.Http do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.Auth.{ActionCsrf, Admission, SessionCookie, RegistrationAttribution}
  alias Dawarich.Auth.Providers.{Completion, Failure, Github, Google, Oidc, State}
  alias DawarichWeb.{AuthCookie, RailsAuth, RequestURL}

  @providers ~w(github google_oauth2 openid_connect)
  @fields ~w(state code error error_reason error_description error_uri nonce scope client authuser prompt hd authenticity_token commit utf8 locale invitation_token import_ticket aff via _gl utm_source utm_medium utm_campaign utm_term utm_content message)
  def init(opts), do: opts
  def route?(conn), do: match?({_, _}, route(conn.request_path))

  def call(conn, opts) do
    if Keyword.get(opts, :enabled, false) and route?(conn) do
      conn = conn |> DawarichWeb.HostAuthorization.call([]) |> DawarichWeb.ForceSSL.call([])
      conn = if conn.halted, do: conn, else: DawarichWeb.RateLimit.call(conn, [])
      if conn.halted, do: conn, else: admit(conn, opts)
    else
      case Keyword.get(opts, :fallback) do
        fun when is_function(fun, 1) -> fun.(conn)
        _ -> conn
      end
    end
  end

  defp admit(conn, opts) do
    context = Keyword.get(opts, :context, %{})

    context =
      context
      |> Map.put_new(
        :self_hosted,
        Dawarich.ReleaseMigration.self_hosted?(Map.get_lazy(context, :env, &System.get_env/0))
      )
      |> Dawarich.Auth.RegistrationCallbacks.context()
      |> Map.put_new(:base_url, RequestURL.base(conn))
      |> Map.put_new(:ip, DawarichWeb.RailsRemoteIp.ip(conn))

    conn = RailsAuth.call(conn, [])
    {provider, action} = route(conn.request_path)

    with :ok <- Admission.headers(conn.req_headers),
         {:ok, params, conn} <- parameters(conn) do
      conn = assign(conn, :rails_session, Completion.client_session(conn, params))

      context =
        Map.put(
          context,
          :locale,
          DawarichWeb.Locale.resolve(params["locale"], nil, conn.assigns.rails_session)
        )

      cond do
        action == :failure ->
          Failure.respond(conn, failure_reason(params["message"]), provider, context)

        action == :authorize and conn.method != "POST" ->
          conn |> send_resp(404, "") |> halt()

        action == :authorize and not csrf?(conn, params) ->
          conn |> send_resp(422, "Invalid authenticity token") |> halt()

        conn.method not in ["GET", "POST"] ->
          conn |> send_resp(404, "") |> halt()

        true ->
          handle(conn, provider, action, params, context)
      end
    else
      _ -> conn |> send_resp(400, "Invalid provider request") |> halt()
    end
  rescue
    _ ->
      Failure.terminal(conn)
  end

  defp handle(conn, provider, action, params, context) do
    case configuration(provider, conn, context) do
      {:ok, config} ->
        module = module(provider)

        case action do
          :authorize ->
            session = session(conn.assigns.rails_session, params, context)
            {:ok, url, session} = module.authorize(config, session)

            conn
            |> AuthCookie.session(SessionCookie.for_form(session, Dawarich.RailsSecret.fetch()))
            |> Failure.redirect_to(url)

          :callback ->
            case State.take(conn.assigns.rails_session, params) do
              {:ok, pending, clean} ->
                conn = assign(conn, :rails_session, clean)
                exchange = fn -> module.callback(config, params, pending, context) end
                Completion.run(conn, provider, exchange, context)

              {:error, reason, clean} ->
                Failure.respond(assign(conn, :rails_session, clean), reason, provider, context)
            end
        end

      {:error, :disabled} ->
        conn |> send_resp(404, "") |> halt()

      {:error, reason} ->
        Failure.respond(conn, reason, provider, context)
    end
  end

  def configuration(provider, conn, context) do
    case get_in(context, [:providers, provider]) do
      config when is_map(config) -> {:ok, config}
      _ -> configured(provider, conn, context)
    end
  end

  defp configured("openid_connect", _conn, %{self_hosted: false}), do: {:error, :disabled}

  defp configured("openid_connect", _conn, context),
    do: Oidc.configuration(Map.get_lazy(context, :env, &System.get_env/0), context)

  defp configured(_, _, %{self_hosted: true}), do: {:error, :disabled}

  defp configured(provider, conn, context) do
    env = Map.get_lazy(context, :env, &System.get_env/0)
    prefix = if provider == "github", do: "GITHUB", else: "GOOGLE"
    id = env[prefix <> "_OAUTH_CLIENT_ID"]
    secret = env[prefix <> "_OAUTH_CLIENT_SECRET"]

    if is_binary(id) and id != "" and is_binary(secret) and secret != "" do
      base = %{
        client_id: id,
        client_secret: secret,
        redirect_uri: RequestURL.base(conn) <> "/users/auth/" <> provider <> "/callback"
      }

      endpoints =
        if provider == "github" do
          %{
            authorization_endpoint: "https://github.com/login/oauth/authorize",
            token_endpoint: "https://github.com/login/oauth/access_token",
            userinfo_endpoint: "https://api.github.com/user",
            emails_endpoint: "https://api.github.com/user/emails",
            scope: "user:email"
          }
        else
          %{
            authorization_endpoint: "https://accounts.google.com/o/oauth2/auth",
            token_endpoint: "https://oauth2.googleapis.com/token",
            userinfo_endpoint: "https://www.googleapis.com/oauth2/v3/userinfo",
            jwks_uri: "https://www.googleapis.com/oauth2/v3/certs"
          }
        end

      {:ok, Map.merge(base, endpoints)}
    else
      {:error, :disabled}
    end
  end

  defp session(session, params, context) do
    session =
      if context.self_hosted, do: session, else: RegistrationAttribution.store(session, params)

    session =
      Enum.reduce(
        [{"invitation_token", "invitation_token"}, {"import_ticket", "pending_import_ticket"}],
        session,
        fn {param, key}, acc ->
          if params[param], do: Map.put(acc, key, params[param]), else: acc
        end
      )

    session
  end

  defp parameters(%{method: "POST"} = conn) do
    with [type] <- get_req_header(conn, "content-type"),
         true <- hd(String.split(type, ";")) == "application/x-www-form-urlencoded",
         {:ok, body, conn} <- raw_body(conn),
         {:ok, params} <- Admission.form(body, "", @fields),
         {:ok, query} <- Admission.form(conn.query_string, "", @fields),
         true <- Enum.all?(Map.keys(query), &(not Map.has_key?(params, &1))) do
      {:ok, Map.merge(query, params), conn}
    else
      _ -> :error
    end
  end

  defp parameters(conn) do
    with {:ok, params} <- Admission.form(conn.query_string, "", @fields), do: {:ok, params, conn}
  end

  defp csrf?(conn, params) do
    get_req_header(conn, "origin") in [[], [RequestURL.base(conn)]] and
      Enum.any?(
        [params["authenticity_token"] | get_req_header(conn, "x-csrf-token")],
        &ActionCsrf.valid?(conn.assigns.rails_session, &1, "POST", conn.request_path)
      )
  end

  defp module("github"), do: Github
  defp module("google_oauth2"), do: Google
  defp module("openid_connect"), do: Oidc
  defp route("/users/auth/failure"), do: {"openid_connect", :failure}

  defp route(path) do
    case String.split(path, "/", trim: true) do
      ["users", "auth", provider] when provider in @providers -> {provider, :authorize}
      ["users", "auth", provider, "callback"] when provider in @providers -> {provider, :callback}
      _ -> nil
    end
  end

  defp failure_reason("csrf_detected"), do: :csrf_detected
  defp failure_reason("invalid_credentials"), do: :invalid_credentials
  defp failure_reason("timeout"), do: :timeout
  defp failure_reason(_), do: :access_denied
  defp raw_body(%{private: %{dawarich_raw_body: raw}} = conn), do: {:ok, raw, conn}
  defp raw_body(conn), do: read_body(conn, length: 65536)
end
