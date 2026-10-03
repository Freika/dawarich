defmodule DawarichWeb.InsightsGate do
  @moduledoc "Admission for the Insights details GET and the signed-in home redirect."
  alias Dawarich.Auth.Admission
  alias Dawarich.Insights.Details
  alias DawarichWeb.{RailsAuth, Strangler}

  def owned?(%{path_info: []} = conn, _params),
    do: "insights" not in Application.get_env(:dawarich, :rails_routes, []) and user(conn) != nil

  def owned?(conn, _params) do
    query = Plug.Conn.Query.decode(conn.query_string)
    strings = Enum.all?(~w(year month), &(is_nil(query[&1]) or is_binary(query[&1])))

    case strings && user(conn) do
      user when is_map(user) -> not Details.load(user, query).rails
      _ -> false
    end
  end

  defp user(conn) do
    conn = RailsAuth.call(conn, [])

    if conn.assigns.rails_locked == nil and Strangler.page_request?(conn) and
         Admission.headers(conn.req_headers) == :ok,
       do: conn.assigns.current_user
  end
end
