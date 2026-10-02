defmodule DawarichWeb.PlacesGate do
  @moduledoc false

  alias Dawarich.PlaceList
  alias DawarichWeb.TripsGate

  def index?(conn, _params) do
    case Plug.Conn.Query.decode(conn.query_string)["page"] do
      page when is_binary(page) or is_nil(page) ->
        TripsGate.open?(conn, &(PlaceList.load(&1, page) != :rails))

      _page ->
        false
    end
  end
end
