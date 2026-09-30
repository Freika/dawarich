defmodule DawarichWeb.TripsGate do
  @moduledoc false

  alias Dawarich.TripList

  def index?(conn, _params) do
    case Plug.Conn.Query.decode(conn.query_string)["page"] do
      page when is_binary(page) or is_nil(page) ->
        open?(conn, &(TripList.gate(&1, page_number(page)) == :phoenix))

      _page ->
        false
    end
  end

  def page_number(page), do: max(DawarichWeb.Params.ruby_to_i(page), 1)

  defp open?(conn, check) do
    case DawarichWeb.RailsAuth.call(conn, []).assigns.current_user do
      nil -> true
      user -> check.(user)
    end
  end
end
