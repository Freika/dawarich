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
    {sid, Map.put(session, @rails_user, DawarichWeb.RailsAuth.user_id(conn))}
  end

  @impl true
  def put(conn, sid, session, opts),
    do: COOKIE.put(conn, sid, Map.delete(session, @rails_user), opts)

  @impl true
  def delete(conn, sid, opts), do: COOKIE.delete(conn, sid, opts)
end
