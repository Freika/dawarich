defmodule DawarichWeb.SharingGate do
  @moduledoc false

  import Plug.Conn, only: [get_req_header: 2]

  alias Dawarich.SharedLinks
  alias DawarichWeb.{LayoutAssigns, RailsAuth, RailsProxy}

  @forwarded ~w(forwarded x-forwarded-for)

  def show?(conn, %{"id" => id}),
    do: open?(conn, id) and not RailsProxy.Headers.body?(conn) and renderable?(id)

  def unlock?(conn, %{"id" => id}),
    do:
      open?(conn, id) and Enum.all?(@forwarded, &(get_req_header(conn, &1) == [])) and
        is_pid(Process.whereis(Dawarich.Redis.rack_attack()))

  defp open?(conn, id) do
    conn.method != "HEAD" and LayoutAssigns.self_hosted?() and SharedLinks.canonical?(id) and
      get_req_header(conn, "x-dawarich-client") == [] and
      not Map.has_key?(Plug.Conn.Query.decode(conn.query_string), "client") and
      anonymous?(RailsAuth.call(conn, []))
  end

  defp anonymous?(conn),
    do:
      is_nil(conn.assigns.current_user) and is_nil(conn.cookies["remember_user_token"]) and
        Enum.all?(
          ~w(warden.user.user.key flash),
          &(not Map.has_key?(conn.assigns.rails_session, &1))
        )

  defp renderable?(id) do
    case SharedLinks.active(id, DateTime.utc_now()) do
      nil -> true
      link -> SharedLinks.page(link) != :rails
    end
  end
end
