defmodule DawarichWeb.VisitRequestGate do
  @moduledoc false
  alias Dawarich.Visits.WebSettings
  alias DawarichWeb.{RailsAuth, Strangler}

  def actions?(conn, _params), do: DawarichWeb.LayoutAssigns.self_hosted?() and query?(conn)

  defp query?(conn), do: conn.query_string == ""

  def navigation?(conn, _params) do
    Strangler.page_request?(conn) and
      DawarichWeb.A8Gate.scalar_query?(conn.query_string, ~w(status locale))
  end

  def settings?(conn, _params) do
    DawarichWeb.LayoutAssigns.self_hosted?() and
      DawarichWeb.A8Gate.scalar_query?(conn.query_string, ~w(locale)) and
      case RailsAuth.call(conn, []).assigns.current_user do
        nil ->
          true

        user ->
          WebSettings.page(
            user,
            WebSettings.load(Dawarich.Repo, user.id),
            DateTime.utc_now(),
            DawarichWeb.LayoutAssigns.self_hosted?()
          ) != :rails
      end
  end
end
