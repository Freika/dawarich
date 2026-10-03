defmodule DawarichWeb.PlacesGate do
  @moduledoc false

  alias Dawarich.{PlaceDrawer, PlaceList}
  alias DawarichWeb.TripsGate

  def index?(conn, _params) do
    case Plug.Conn.Query.decode(conn.query_string)["page"] do
      page when is_binary(page) or is_nil(page) ->
        valued?(conn.query_string) and
          TripsGate.open?(conn, &(PlaceList.load(&1, page) != :rails))

      _page ->
        false
    end
  end

  def drawer?(conn, %{"id" => id}) do
    Plug.Conn.get_req_header(conn, "turbo-frame") == ["place-drawer"] and conn.query_string == "" and
      Plug.Conn.get_req_header(conn, "x-dawarich-client") == [] and
      TripsGate.open?(conn, &(PlaceDrawer.load(&1, String.to_integer(id)) != :rails))
  end

  defp valued?(query),
    do: query |> String.split("&", trim: true) |> Enum.all?(&String.contains?(&1, "="))
end
