defmodule DawarichWeb.InsightsGate do
  @moduledoc "Admission for the Insights details GET and the signed-in home redirect."
  alias Dawarich.Auth.Admission
  alias DawarichWeb.{RailsAuth, Strangler}

  def owned?(%{path_info: []} = conn, _params),
    do: "insights" not in Application.get_env(:dawarich, :rails_routes, []) and signed_in?(conn)

  def owned?(conn, _params) do
    query = Plug.Conn.Query.decode(conn.query_string)
    Enum.all?(~w(year month), &(is_nil(query[&1]) or is_binary(query[&1]))) and signed_in?(conn)
  end

  defp signed_in?(conn) do
    conn = RailsAuth.call(conn, [])

    conn.assigns.current_user != nil and conn.assigns.rails_locked == nil and
      Strangler.page_request?(conn) and Admission.headers(conn.req_headers) == :ok
  end
end
