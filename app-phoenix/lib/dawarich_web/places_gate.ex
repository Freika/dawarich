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
      TripsGate.open?(conn, fn user ->
        PlaceDrawer.load(user, String.to_integer(id)) != :rails or
          (Dawarich.Standalone.enabled?() and
             Dawarich.Repo.query!(
               "SELECT id FROM places WHERE id=$1 AND user_id=$2",
               [String.to_integer(id), user.id],
               log: false
             ).rows == [])
      end)
  end

  def navigation?(conn, params) do
    case Plug.Conn.get_req_header(conn, "turbo-frame") do
      ["place-drawer"] -> drawer?(conn, params)
      [] -> conn.query_string == "" and Plug.Conn.get_req_header(conn, "x-dawarich-client") == []
      _ -> false
    end
  end

  def nearby?(conn, _params) do
    Plug.Conn.get_req_header(conn, "x-dawarich-client") == [] and valued?(conn.query_string) and
      scalar_nearby?(conn.query_string) and
      TripsGate.open?(conn, fn _user -> true end)
  end

  defp scalar_nearby?(query) do
    pairs = URI.query_decoder(query) |> Enum.to_list()

    Enum.all?(pairs, fn {key, value} ->
      key in ~w(latitude longitude radius limit) and String.valid?(value)
    end) and
      length(pairs) == length(Enum.uniq_by(pairs, &elem(&1, 0)))
  rescue
    _ -> false
  end

  defp valued?(query),
    do: query |> String.split("&", trim: true) |> Enum.all?(&String.contains?(&1, "="))
end
