defmodule DawarichWeb.MapFrameRoutes do
  @moduledoc false
  defmacro map_frame_routes do
    quote do
      scope "/map" do
        pipe_through :rails_frame

        get "/residency", DawarichWeb.MapFrames, :residency
      end

      scope "/places" do
        pipe_through :rails_frame

        get "/nearby", DawarichWeb.PlaceNavigation, :nearby

        get "/:id", DawarichWeb.PlaceNavigation, :show
      end
    end
  end
end
