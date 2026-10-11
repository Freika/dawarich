defmodule DawarichWeb.MapFrameRoutes do
  @moduledoc false
  defmacro map_frame_routes do
    quote do
      scope "/map" do
        pipe_through :rails_frame

        get "/residency", DawarichWeb.MapFrames, :residency,
          metadata: %{rails_gate: {DawarichWeb.MapFramesGate, :residency?}}
      end

      scope "/places" do
        pipe_through :rails_frame

        get "/nearby", DawarichWeb.PlaceNavigation, :nearby,
          metadata: %{rails_gate: {DawarichWeb.PlacesGate, :nearby?}}

        get "/:id", DawarichWeb.PlaceNavigation, :show,
          metadata: %{rails_gate: {DawarichWeb.PlacesGate, :navigation?}}
      end
    end
  end
end
