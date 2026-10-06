defmodule DawarichWeb.AuthAccount.Destroy do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.Auth.{AccountDestroy, ActionCsrf, Admission, SessionCookie}
  alias DawarichWeb.{AuthCookie, RailsAuth, RequestURL}

  def init(opts), do: opts

  def route?(conn),
    do:
      {conn.method, conn.request_path} in [
        {"DELETE", "/users"},
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

  defp dispatch(conn, opts) do
    with user when not is_nil(user) <- conn.assigns.current_user,
         :ok <- Admission.headers(conn.req_headers),
         [type] <- get_req_header(conn, "content-type"),
         true <- hd(String.split(type, ";")) == "application/x-www-form-urlencoded",
         {:ok, body, conn} <- read_body(conn, length: 65_536, read_length: 65_536),
         {:ok, params} <- Admission.form(body, "", ~w(password confirm_email authenticity_token)),
         true <- get_req_header(conn, "origin") in [[], [RequestURL.base(conn)]],
         true <-
           ActionCsrf.valid?(
             conn.assigns.rails_session,
             params["authenticity_token"],
             "DELETE",
             "/users"
           ) do
      result = AccountDestroy.request(user.id, params, context(conn, opts))
      respond(conn, result, if(result == {:ok, :scheduled}, do: "/", else: "/users/edit"))
    else
      _ -> conn |> send_resp(422, "Invalid account deletion request") |> halt()
    end
  end

  defp respond(conn, {:ok, :scheduled}, path) do
    if conn.method != "GET" or
         (conn.assigns.current_user &&
            conn.assigns.current_user.id == conn.private[:destroy_actor_id]) do
      conn
      |> AuthCookie.session(
        SessionCookie.for_logout(
          "Your account has been scheduled for deletion.",
          Dawarich.RailsSecret.fetch()
        )
      )
      |> AuthCookie.forget()
      |> redirect(path)
    else
      redirect(conn, path)
    end
  end

  defp respond(conn, {:ok, :sent}, path), do: redirect(conn, path)

  defp respond(conn, {:error, error}, path)
       when error in [
              :replayed,
              :invalid_token,
              :actor,
              :cannot_delete_account,
              :password_required,
              :rate_limited
            ],
       do: redirect(conn, path)

  defp respond(conn, {:error, _}, _),
    do: conn |> send_resp(503, "Account deletion unavailable") |> halt()

  defp redirect(conn, path),
    do:
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("pragma", "no-cache")
      |> put_resp_header("location", RequestURL.base(conn) <> path)
      |> send_resp(302, "")
      |> halt()

  defp context(conn, opts),
    do:
      Keyword.get(opts, :context, Application.get_env(:dawarich, :account_destroy_context, %{}))
      |> Map.put_new(:self_hosted, System.get_env("SELF_HOSTED", "true") != "false")
      |> Map.put_new(:base_url, RequestURL.base(conn))
end
