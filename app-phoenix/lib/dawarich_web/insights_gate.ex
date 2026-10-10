defmodule DawarichWeb.InsightsGate do
  @moduledoc "Admission for the Insights details GET and the signed-in home redirect."
  alias Dawarich.Auth.Admission
  alias DawarichWeb.{RailsAuth, Strangler}

  def owned?(%{path_info: []} = conn, _params),
    do: "insights" not in Application.get_env(:dawarich, :rails_routes, []) and user(conn) != nil

  def owned?(conn, _params) do
    Strangler.page_request?(conn) and Admission.headers(conn.req_headers) == :ok
  end

  defp user(conn) do
    conn = RailsAuth.call(conn, [])

    if conn.assigns.rails_locked == nil and Strangler.page_request?(conn) and
         Admission.headers(conn.req_headers) == :ok,
       do: conn.assigns.current_user
  end
end
