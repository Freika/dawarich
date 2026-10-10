defmodule Dawarich.Test.ShareReviewRouter do
  use Phoenix.Router
  require DawarichWeb.TrackShareRoutes
  require DawarichWeb.ShareManagementOverrideRoutes
  require DawarichWeb.TimelineShareRoutes

  pipeline :rails_frame do
    plug :fetch_query_params
    plug DawarichWeb.RailsAuth
    plug DawarichWeb.Locale
  end

  pipeline :share_form do
    plug :tag
    plug DawarichWeb.Api.Body, nested_form: "shared_link"
    plug DawarichWeb.RailsAuth
    plug :admit
  end

  DawarichWeb.TrackShareRoutes.routes()
  DawarichWeb.TimelineShareRoutes.routes()
  DawarichWeb.ShareManagementOverrideRoutes.routes()

  defp tag(conn, _), do: Plug.Conn.assign(conn, :api_tag, "sharing")
  defp admit(conn, _), do: DawarichWeb.ShareManagementForm.admit(conn, [])
end
