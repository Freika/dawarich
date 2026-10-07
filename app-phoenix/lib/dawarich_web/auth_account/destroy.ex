defmodule DawarichWeb.AuthAccount.Destroy do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.Auth.{AccountDestroy, ActionCsrf, Admission, SessionCookie}
  alias DawarichWeb.{AuthCookie, RailsAuth, RailsSession, RequestURL}

  def init(opts), do: opts

  def route?(conn),
    do:
      {conn.method, conn.request_path} in [
        {"DELETE", "/users"},
        {"POST", "/users"},
        {"GET", "/users/me/destroy/confirm"}
      ]

  def call(conn, opts) do
    if Keyword.get(opts, :enabled, false) and route?(conn) do
      conn = conn |> DawarichWeb.HostAuthorization.call([]) |> DawarichWeb.ForceSSL.call([])
      if conn.halted, do: conn, else: dispatch(RailsAuth.call(conn, []), opts)
    else
      conn
    end
  end

  defp dispatch(%{method: "GET"} = conn, opts) do
    conn = fetch_query_params(conn)
    ctx = context(conn, opts)

    conn =
      case Dawarich.Auth.DestroyToken.verify(conn.query_params["token"], ctx) do
        {:ok, claims} -> put_private(conn, :destroy_actor_id, claims["user_id"])
        _ -> conn
      end

    respond(conn, AccountDestroy.confirm(conn.query_params["token"], ctx), "/users/sign_in")
  end

  defp dispatch(%{assigns: %{current_user: nil}} = conn, _opts) do
    conn
    |> flash(:alert, text(conn, "devise.failure.unauthenticated"))
    |> redirect("/users/sign_in")
  end

  defp dispatch(conn, opts) do
    with :ok <- Admission.headers(conn.req_headers),
         [type] <- get_req_header(conn, "content-type"),
         true <- hd(String.split(type, ";")) == "application/x-www-form-urlencoded",
         {:ok, body, conn} <- body(conn),
         {:ok, params} <-
           Admission.form(
             body,
             conn.query_string,
             ~w(password confirm_email authenticity_token commit utf8 _method id)
           ),
         true <- valid_method?(conn, params),
         true <- csrf?(conn, params) do
      result = AccountDestroy.request(conn.assigns.current_user.id, params, context(conn, opts))
      respond(conn, result, if(result == {:ok, :scheduled}, do: "/", else: "/users/edit"))
    else
      _ -> conn |> send_resp(422, "Invalid account deletion request") |> halt()
    end
  end

  defp body(%{private: %{dawarich_raw_body: raw}} = conn) when byte_size(raw) <= 65_536,
    do: {:ok, raw, conn}

  defp body(conn), do: read_body(conn, length: 65_536, read_length: 65_536)

  defp csrf?(conn, params) do
    tokens =
      Enum.reject(
        [params["authenticity_token"] | get_req_header(conn, "x-csrf-token")],
        &is_nil/1
      )

    get_req_header(conn, "origin") in [[], [RequestURL.base(conn)]] and
      Enum.any?(tokens, &ActionCsrf.valid?(conn.assigns.rails_session, &1, "DELETE", "/users"))
  end

  defp valid_method?(%{method: "POST"}, params), do: params["_method"] == "delete"
  defp valid_method?(%{method: "DELETE"}, params), do: params["_method"] in [nil, "delete"]

  defp respond(conn, {:ok, :scheduled}, path) do
    notice =
      if conn.method == "GET",
        do:
          text(
            conn,
            "controllers.users.destroy_confirmations.your_account_has_been_scheduled_for_deletion_we_are_sorry"
          ),
        else:
          text(
            conn,
            "controllers.users.registrations.your_account_has_been_scheduled_for_deletion"
          )

    conn =
      if conn.method != "GET" or
           (conn.assigns.current_user &&
              conn.assigns.current_user.id == conn.private[:destroy_actor_id]) do
        conn
        |> AuthCookie.session(SessionCookie.for_logout(notice, Dawarich.RailsSecret.fetch()))
        |> AuthCookie.forget()
      else
        flash(conn, :notice, notice)
      end

    redirect(conn, path)
  end

  defp respond(conn, {:ok, :sent}, path), do: conn |> flash(:notice, sent()) |> redirect(path)

  defp respond(conn, {:error, error}, path)
       when error in [
              :replayed,
              :invalid_token,
              :actor,
              :cannot_delete_account,
              :password_required,
              :rate_limited
            ],
       do: conn |> flash(:alert, error_message(conn, error)) |> redirect(path)

  defp respond(conn, {:error, _}, _),
    do: conn |> send_resp(503, "Account deletion unavailable") |> halt()

  defp error_message(_conn, :rate_limited),
    do:
      "A confirmation email was already sent recently. Check your inbox or wait an hour before requesting another one."

  defp error_message(conn, :password_required) do
    provider = conn.assigns.current_user.provider

    key =
      if Dawarich.Auth.Recovery.Token.blank?(provider),
        do: "confirm_with_password",
        else: "confirm_with_email"

    text(conn, "controllers.concerns.account_deletion_confirmable." <> key)
  end

  defp error_message(conn, error) do
    key =
      case error do
        :replayed ->
          "controllers.users.destroy_confirmations.this_deletion_link_has_already_been_used"

        :cannot_delete_account when conn.method == "GET" ->
          "controllers.users.destroy_confirmations.cannot_delete_account_while_you_own_a_family_with_other"

        :cannot_delete_account ->
          "devise.registrations.cannot_delete"

        _ ->
          "controllers.users.destroy_confirmations.deletion_link_invalid_or_expired"
      end

    text(conn, key)
  end

  defp sent,
    do:
      "A confirmation email has been sent. Click the link in the email to permanently delete your account."

  defp flash(conn, kind, message),
    do:
      RailsSession.put(conn, %{
        "flash" => %{"discard" => [], "flashes" => %{to_string(kind) => message}}
      })

  defp text(conn, key) do
    locale =
      DawarichWeb.Locale.resolve(nil, conn.assigns.current_user, conn.assigns.rails_session)

    {:ok, message} = Dawarich.I18n.t(locale, key)
    message
  end

  defp redirect(conn, path),
    do:
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("pragma", "no-cache")
      |> put_resp_header("location", RequestURL.base(conn) <> path)
      |> send_resp(302, "")
      |> halt()

  defp context(conn, opts) do
    context =
      Keyword.get(opts, :context, Application.get_env(:dawarich, :account_destroy_context, %{})) ||
        %{}

    context
    |> Map.put_new(:self_hosted, System.get_env("SELF_HOSTED", "true") != "false")
    |> Map.put_new(:base_url, AccountDestroy.mail_base_url(context, RequestURL.base(conn)))
    |> AccountDestroy.context()
  end
end
