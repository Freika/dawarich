defmodule DawarichWeb.AuthAccountLink.Response do
  @moduledoc false
  import Plug.Conn
  alias Dawarich.{RailsSecret, Auth.SessionCookie}
  alias Dawarich.Auth.Recovery.Token

  alias DawarichWeb.{
    AuthCookie,
    LayoutAssigns,
    Layouts,
    Locale,
    RailsCsrf,
    RailsHeaders,
    RequestURL
  }

  alias DawarichWeb.AuthAccountLink.Form

  def form(conn, pending, context \\ %{}) do
    conn = conn |> assign(:rails_session, pending.session) |> prepare()
    {session, _} = encoded = SessionCookie.for_form(conn.assigns.rails_session, secret(context))

    assigns =
      Map.merge(conn.assigns, %{
        __changed__: nil,
        flash: %{},
        page_title: Form.title(conn.assigns.locale),
        provider_label: label(pending.pending, conn.assigns.locale),
        user_email: pending.user.email,
        confirm_csrf_token:
          RailsCsrf.masked_form_token(session, "/auth/account_link/challenge", "POST"),
        email_csrf_token: RailsCsrf.masked_form_token(session, "/auth/account_link/email", "POST")
      })

    body = Form.page(Map.put(assigns, :flash, Map.new(conn.assigns.flash_messages)))
    app = Layouts.app(Map.put(assigns, :inner_content, body))
    html = Layouts.root(Map.put(assigns, :inner_content, app)) |> Phoenix.HTML.Safe.to_iodata()

    conn
    |> AuthCookie.session(encoded)
    |> headers()
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
    |> halt()
  end

  def completed(conn, result, context \\ %{}) do
    conn = conn |> assign(:rails_session, result.session) |> prepare()
    {encoded, path} = completion_cookie(conn, result, context)

    conn
    |> AuthCookie.session(encoded)
    |> headers()
    |> put_resp_content_type("text/html")
    |> put_resp_header("location", RequestURL.base(conn) <> path)
    |> send_resp(302, "")
    |> halt()
  end

  def preflight(conn, result, context) do
    conn = conn |> assign(:rails_session, result.session) |> prepare()
    completion_cookie(conn, result, context)
    :ok
  end

  defp completion_cookie(conn, result, context) do
    {key, binding, path} =
      if result.kind == :sign_in,
        do: {"pending_is_now_linked_to_your_account", "pending", "/"},
        else: {"linked_sign_in_with_two_factor", "provider", "/users/sign_in"}

    {:ok, notice} =
      Dawarich.I18n.t(conn.assigns.locale, "controllers.auth.account_links." <> key, %{
        binding => label(result.pending, conn.assigns.locale)
      })

    encoded =
      SessionCookie.for_account_link(
        result.session,
        result.user,
        result.kind,
        notice,
        secret(context)
      )

    {encoded, path}
  end

  defp prepare(conn),
    do: conn |> fetch_query_params() |> Locale.call([]) |> LayoutAssigns.call([])

  defp secret(context), do: Map.get_lazy(context, :secret, &RailsSecret.fetch/0)

  defp label(pending, _locale) do
    if Token.blank?(pending["provider_label"]) do
      System.get_env("OIDC_PROVIDER_NAME", "Openid Connect")
    else
      pending["provider_label"]
    end
  end

  defp headers(conn),
    do:
      conn
      |> RailsHeaders.call([])
      |> put_resp_header("x-dawarich-auth-owner", "native-account-link")
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("pragma", "no-cache")
end
