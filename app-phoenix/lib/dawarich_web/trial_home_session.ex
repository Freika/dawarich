defmodule DawarichWeb.TrialHomeSession do
  @moduledoc false
  alias Dawarich.Auth.SessionCookie
  alias Dawarich.RailsSecret
  alias DawarichWeb.{AuthCookie, LayoutAssigns}
  def init(opts), do: opts

  def call(conn, _opts) do
    params = Plug.Conn.Query.decode(conn.query_string)
    session = conn.assigns.rails_session
    pending = conn.private[:dawarich_rails_session_changes] || %{}
    updated = session |> Map.merge(pending) |> client(conn, params) |> referral(params)

    if updated == session do
      conn
    else
      AuthCookie.session(conn, SessionCookie.for_form(updated, RailsSecret.fetch()))
    end
  end

  defp client(session, conn, params) do
    value = List.first(Plug.Conn.get_req_header(conn, "x-dawarich-client")) || params["client"]
    if value in ~w(ios android), do: Map.put(session, "dawarich_client", value), else: session
  end

  defp referral(session, params) do
    value =
      Enum.find_value(~w(aff via), fn key ->
        value = params[key]
        if is_binary(value) and String.trim(value) != "", do: value
      end)

    if not LayoutAssigns.self_hosted?() and value,
      do: Map.put(session, "partnero_referral", String.slice(value, 0, 255)),
      else: session
  end
end
