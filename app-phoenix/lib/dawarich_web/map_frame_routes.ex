defmodule DawarichWeb.MapFrameRoutes do
  @moduledoc false
  defmacro map_frame_routes do
    quote do
      scope "/" do
        pipe_through :map_write

        for method <- [:patch, :put, :post] do
          match method, "/tracks/:track_id/segments/:id", DawarichWeb.SegmentActions, :update,
            metadata: %{rails_gate: {DawarichWeb.MapWriteGate, :owned?}}
        end
      end

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

        get "/nearby", DawarichWeb.PlaceNavigation, :nearby,
          metadata: %{rails_gate: {DawarichWeb.PlacesGate, :nearby?}}

        get "/:id", DawarichWeb.PlaceNavigation, :show,
          metadata: %{rails_gate: {DawarichWeb.PlacesGate, :navigation?}}
      end

      scope "/" do
        pipe_through :rails_frame

        get "/tracks/:track_id/segments", DawarichWeb.MapFrames, :segments,
          metadata: %{rails_gate: {DawarichWeb.MapDataGate, :segments?}}

        get "/points/:id/address", DawarichWeb.PointAddress, :address,
          metadata: %{rails_gate: {DawarichWeb.MapDataGate, :point_address?}}
      end
    end
  end
end
