defmodule DawarichWeb.RailsPageRoutes do
  @moduledoc false

  defmacro rails_page_routes do
    quote do
      live "/notifications", DawarichWeb.NotificationsLive.Index, :index,
        container: {:div, class: "contents"}

      live "/notifications/:id", DawarichWeb.NotificationsLive.Show, :show,
        container: {:div, class: "contents"}

      live "/imports/new", DawarichWeb.ImportsLive.New, :new, container: {:div, class: "contents"}

      live "/imports/:id", DawarichWeb.ImportsLive.Show, :show,
        container: {:div, class: "contents"},
        metadata: @native_import

      live "/imports", DawarichWeb.ImportsLive.Index, :index, container: {:div, class: "contents"}
      live "/exports", DawarichWeb.ExportsLive.Index, :index, container: {:div, class: "contents"}
      live "/stats", DawarichWeb.StatsLive.Index, :index, container: {:div, class: "contents"}
      live "/stats/:year", DawarichWeb.StatsLive.Year, :show, container: {:div, class: "contents"}

      live "/stats/:year/:month", DawarichWeb.StatsLive.Month, :month,
        container: {:div, class: "contents"}

      live "/digests", DawarichWeb.DigestsLive.Index, :index, container: {:div, class: "contents"}

      live "/digests/:year", DawarichWeb.DigestsLive.Show, :show,
        container: {:div, class: "contents"}

      live "/trips", DawarichWeb.TripsLive.Index, :index,
        container: {:div, class: "contents"},
        metadata: %{rails_gate: {DawarichWeb.TripsGate, :index?}}

      live "/trips/:id", DawarichWeb.TripsLive.Show, :show,
        container: {:div, class: "contents"},
        metadata: %{rails_gate: {DawarichWeb.TripsGate, :show?}}

      live "/places", DawarichWeb.PlacesLive.Index, :index,
        container: {:div, class: "contents"},
        metadata: %{rails_gate: {DawarichWeb.PlacesGate, :index?}}

      live "/settings/general", DawarichWeb.SettingsLive.General, :index,
        container: {:div, class: "contents"}

      live "/settings/integrations", DawarichWeb.SettingsLive.Integrations, :index,
        container: {:div, class: "contents"}

      live "/users/edit", DawarichWeb.AccountLive.Edit, :edit,
        container: {:div, class: "contents"}

      live "/insights", DawarichWeb.InsightsLive.Index, :index,
        container: {:div, class: "contents"}
    end
  end

  defmacro rails_frame_routes do
    quote do
      scope "/map" do
        pipe_through :rails_frame

        get "/timeline_feeds", DawarichWeb.MapFrames, :index,
          metadata: %{rails_gate: {DawarichWeb.MapFramesGate, :feed?}}

        get "/timeline_feeds/calendar", DawarichWeb.MapFrames, :calendar,
          metadata: %{rails_gate: {DawarichWeb.MapFramesGate, :calendar?}}

        get "/residency", DawarichWeb.MapFrames, :residency,
          metadata: %{rails_gate: {DawarichWeb.MapFramesGate, :residency?}}

        get "/timeline_feeds/:id/track_info", DawarichWeb.MapFrames, :track_info,
          metadata: %{rails_gate: {DawarichWeb.MapFramesGate, :track?}}
      end

      scope "/places" do
        pipe_through :rails_frame

        get "/:id", DawarichWeb.MapFrames, :place,
          metadata: %{rails_gate: {DawarichWeb.PlacesGate, :drawer?}}
      end
    end
  end
end
