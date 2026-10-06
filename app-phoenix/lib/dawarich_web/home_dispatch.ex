defmodule DawarichWeb.HomeDispatch do
  @moduledoc false
  alias DawarichWeb.{InsightsHome, LayoutAssigns, PublicHomeLive, RailsAuth, RailsProxy}
  def init(opts), do: opts

  def call(conn, _opts) do
    conn = conn |> RailsAuth.call([]) |> DawarichWeb.TrialHomeSession.call([])

    if conn.assigns.current_user do
      InsightsHome.index(conn, %{})
    else
      case PublicHomeLive.registration(LayoutAssigns.self_hosted?()) do
        {:ok, enabled} ->
          Phoenix.LiveView.Controller.live_render(conn, PublicHomeLive,
            session: Map.put(RailsAuth.live_session(conn), "registration_enabled", enabled),
            layout: {DawarichWeb.Layouts, :app}
          )

        :error ->
          if Dawarich.Standalone.enabled?(),
            do: DawarichWeb.StandaloneError.respond(conn, "registration_unavailable", 503),
            else: RailsProxy.call(conn, Application.fetch_env!(:dawarich, :rails_upstream))
      end
    end
  end
end
