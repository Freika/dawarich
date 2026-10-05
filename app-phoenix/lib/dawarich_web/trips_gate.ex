defmodule DawarichWeb.TripsGate do
  @moduledoc false

  alias Dawarich.TripList

  def index?(conn, _params) do
    case Plug.Conn.Query.decode(conn.query_string)["page"] do
      page when is_binary(page) or is_nil(page) ->
        family_page = Plug.Conn.Query.decode(conn.query_string)["family_page"]

        (is_nil(family_page) or is_binary(family_page)) and
          page_number(family_page) <= 1_000_000_000_000 and
          open?(conn, &(TripList.gate(&1, page_number(page)) == :phoenix))

      _page ->
        false
    end
  end

  def show?(conn, %{"id" => id}),
    do:
      open?(
        conn,
        &Dawarich.Trips.ShowCalculation.admitted?(
          Dawarich.Repo,
          &1,
          String.to_integer(id),
          conn.assigns[:now] || DateTime.utc_now()
        )
      )

  def form?(conn, params) do
    DawarichWeb.LayoutAssigns.self_hosted?() and conn.query_string == "" and
      open?(conn, fn user ->
        id = params["id"] && String.to_integer(params["id"])
        match?({:ok, _}, Dawarich.Trips.WebForm.load(Dawarich.Repo, user, id, %{}))
      end)
  end

  def page_number(page), do: max(DawarichWeb.Params.ruby_to_i(page), 1)

  def open?(conn, check) do
    case DawarichWeb.RailsAuth.call(conn, []).assigns.current_user do
      nil -> true
      user -> check.(user)
    end
  end
end
