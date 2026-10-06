defmodule DawarichWeb.SessionStore do
  @moduledoc false
  @behaviour Plug.Session.Store

  alias Plug.Session.COOKIE

  @rails_user "rails_user_id"

  @impl true
  def init(opts), do: COOKIE.init(opts)

  @impl true
  def get(conn, cookie, opts) do
    {sid, session} = COOKIE.get(conn, cookie, opts)

    conn =
      if Map.has_key?(conn.private, :dawarich_rails_user),
        do: conn,
        else: DawarichWeb.RailsAuth.call(conn, [])

    session =
      session
      |> Map.put(@rails_user, DawarichWeb.RailsAuth.user_id(conn))
      |> Map.put("operator_login", DawarichWeb.OperatorGrant.login(conn))

    {sid, session}
  end

  @impl true
  def put(conn, sid, session, opts),
    do: COOKIE.put(conn, sid, Map.drop(session, [@rails_user, "operator_login"]), opts)

  @impl true
  def delete(conn, sid, opts), do: COOKIE.delete(conn, sid, opts)
end
