defmodule DawarichWeb.AuthRegistration.Http do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn

  alias Dawarich.Auth.{
    ActionCsrf,
    Admission,
    Registration,
    RegistrationPolicy,
    RegistrationSetup,
    RegistrationAttribution,
    SessionCookie
  }

  alias DawarichWeb.{AuthCookie, RailsAuth, RailsCsrf, RequestURL}

  @fields ~w(authenticity_token commit utf8 locale invitation_token import_ticket _gl aff via utm_source utm_medium utm_campaign utm_term utm_content user[email] user[password] user[password_confirmation] user[first_name] user[last_name] user[invitation_token] user[signup_intent])
  def init(opts), do: opts

  def route?(conn),
    do: {conn.method, conn.request_path} in [{"GET", "/users/sign_up"}, {"POST", "/users"}]

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
    conn = RailsAuth.call(conn, [])
    context = RegistrationPolicy.context(Keyword.get(opts, :context, %{}))

    with {:ok, params, conn} <- parameters(conn),
         :ok <- Admission.headers(conn.req_headers) do
      token =
        params["user[invitation_token]"] || params["invitation_token"] ||
          conn.assigns.rails_session["invitation_token"]

      invitation = RegistrationPolicy.invitation(token, context)
      email = params["user[email]"] || (invitation && invitation.email) || ""
      locale = DawarichWeb.Locale.resolve(params["locale"], nil, conn.assigns.rails_session)
      context = context |> Map.put(:invitation, invitation) |> Map.put(:locale, locale)
      session = conn.assigns.rails_session

      session =
        if context.self_hosted == false,
          do: RegistrationAttribution.store(session, params),
          else: session

      session =
        if params["import_ticket"],
          do: Map.put(session, "pending_import_ticket", params["import_ticket"]),
          else: session

      conn = assign(conn, :rails_session, session)

      context =
        if params["locale"] || conn.assigns.rails_session["locale"],
          do: Map.put(context, :chosen_locale, locale),
          else: context

      cond do
        conn.assigns.current_user ->
          redirect(conn, "/", nil, 302)

        not RegistrationPolicy.allowed?(context, invitation, email) ->
          redirect(
            conn,
            "/",
            message(locale, RegistrationPolicy.denial_key(context, invitation, email)),
            302
          )

        conn.method == "GET" ->
          form(conn, email, [], context, 200)

        not csrf?(conn, params) ->
          conn |> send_resp(422, "Invalid authenticity token") |> halt()

        true ->
          create(conn, params, context)
      end
    else
      _ -> conn |> send_resp(400, "Invalid registration request") |> halt()
    end
  end

  defp create(conn, params, context) do
    attrs =
      Map.new(
        ~w(email password password_confirmation first_name last_name signup_intent),
        fn key -> {key, params["user[#{key}]"]} end
      )

    if not RegistrationSetup.ready?(context) do
      conn |> send_resp(503, "Signup callbacks unavailable") |> halt()
    else
      case Registration.create(attrs, context) do
        {:ok, user} ->
          case RegistrationSetup.complete(user, attrs, conn.assigns.rails_session, context) do
            {:ok, %{signed_in: true} = result} ->
              conn =
                AuthCookie.session(
                  conn,
                  SessionCookie.for_login(
                    result.session,
                    result.user,
                    message(context.locale, "devise.registrations.signed_up"),
                    Dawarich.RailsSecret.fetch()
                  )
                )

              redirect(conn, result.location, nil, 303)

            {:ok, result} ->
              conn
              |> AuthCookie.session(
                SessionCookie.for_form(result.session, Dawarich.RailsSecret.fetch())
              )
              |> put_resp_header("location", result.location)
              |> send_resp(302, "")
              |> halt()

            {:error, _} ->
              conn |> send_resp(503, "Signup callbacks unavailable") |> halt()
          end

        {:error, %{messages: messages, email: email}} ->
          form(conn, email, messages, context, 422)

        {:error, :denied} ->
          redirect(conn, "/", nil, 302)
      end
    end
  end

  defp form(conn, email, messages, context, status) do
    conn =
      conn
      |> fetch_query_params()
      |> DawarichWeb.Locale.call([])
      |> DawarichWeb.LayoutAssigns.call([])

    {session, _} =
      encoded = SessionCookie.for_form(conn.assigns.rails_session, Dawarich.RailsSecret.fetch())

    token = RailsCsrf.masked_token(session)

    body =
      DawarichWeb.AuthRegistration.Form.render(
        token,
        email,
        messages,
        context.invitation,
        context.locale
      )

    assigns =
      Map.merge(conn.assigns, %{
        __changed__: nil,
        flash: %{},
        page_title: nil,
        rails_csrf_token: token,
        inner_content: Phoenix.HTML.raw(body)
      })

    app = DawarichWeb.Layouts.app(assigns)

    html =
      DawarichWeb.Layouts.root(%{assigns | inner_content: app}) |> Phoenix.HTML.Safe.to_iodata()

    conn
    |> AuthCookie.session(encoded)
    |> DawarichWeb.RailsHeaders.call([])
    |> put_resp_header("x-dawarich-auth-owner", "native-registration")
    |> put_resp_content_type("text/html")
    |> send_resp(status, html)
    |> halt()
  end

  defp redirect(conn, path, alert, status) do
    conn =
      if alert do
        session =
          Map.put(conn.assigns.rails_session, "flash", %{
            "discard" => [],
            "flashes" => %{"alert" => alert}
          })

        AuthCookie.session(conn, SessionCookie.for_form(session, Dawarich.RailsSecret.fetch()))
      else
        conn
      end

    conn
    |> DawarichWeb.RailsHeaders.call([])
    |> put_resp_header("x-dawarich-auth-owner", "native-registration")
    |> put_resp_header("location", RequestURL.base(conn) <> path)
    |> send_resp(status, "")
    |> halt()
  end

  defp parameters(%{method: "GET"} = conn) do
    case Admission.form(conn.query_string, "", @fields) do
      {:ok, params} -> {:ok, params, conn}
      other -> other
    end
  end

  defp parameters(conn) do
    with [type] <- get_req_header(conn, "content-type"),
         true <- hd(String.split(type, ";")) == "application/x-www-form-urlencoded",
         {:ok, body, conn} <- read_body(conn, length: 65_536, read_length: 65_536),
         {:ok, params} <- Admission.form(body, "", @fields) do
      {:ok, params, conn}
    else
      _ -> :error
    end
  end

  defp csrf?(conn, params) do
    origins = get_req_header(conn, "origin")
    tokens = [params["authenticity_token"] | get_req_header(conn, "x-csrf-token")]

    origins in [[], [RequestURL.base(conn)]] and length(get_req_header(conn, "x-csrf-token")) <= 1 and
      Enum.any?(tokens, &ActionCsrf.valid?(conn.assigns.rails_session, &1, "POST", "/users"))
  end

  defp message(locale, key), do: DawarichWeb.Translate.t(locale, key, %{})
end
