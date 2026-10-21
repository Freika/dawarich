defmodule DawarichWeb.AuthenticationRefusal do
  @moduledoc false
  import Plug.Conn
  alias DawarichWeb.{Locale, RailsAuth, RailsHeaders, RequireUser, Translate}

  def respond(conn, context \\ %{}) do
    opts = if context[:secret], do: [secret: context.secret], else: []
    conn = conn |> RailsAuth.call(opts) |> fetch_query_params()
    locale = Locale.resolve(conn.query_params["locale"], nil, conn.assigns.rails_session)
    conn = conn |> assign(:locale, locale) |> RailsHeaders.call([])

    if get_req_header(conn, "accept") == ["application/json"] do
      reason =
        if conn.assigns[:rails_locked],
          do: "devise.failure.locked",
          else: "devise.failure.unauthenticated"

      conn
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_content_type("application/json")
      |> send_resp(401, Jason.encode!(%{error: Translate.t(locale, reason, %{})}))
      |> halt()
    else
      conn |> assign(:current_user, nil) |> RequireUser.call([])
    end
  end
end
