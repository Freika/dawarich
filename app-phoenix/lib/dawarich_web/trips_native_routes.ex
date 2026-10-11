defmodule DawarichWeb.TripsNativeRoutes do
  @moduledoc false

  defmacro trips_routes do
    quote do
      scope "/" do
        pipe_through [:native_data_request, :browser, :rails_user]

        live_session :native_trips,
          session: {DawarichWeb.NativeAuth, :live_session, []},
          on_mount: {DawarichWeb.TripsNative.Access, :require_user},
          root_layout: {DawarichWeb.Layouts, :native_root},
          layout: {DawarichWeb.Layouts, :app} do
          live "/trips/new", DawarichWeb.NativeTripsLive.Form, :new,
            container: {:div, class: "contents"},
            metadata: %{native_page: true}

          live "/trips/:id/edit", DawarichWeb.NativeTripsLive.Form, :edit,
            container: {:div, class: "contents"},
            metadata: %{native_page: true}
        end
      end
    end
  end
end
