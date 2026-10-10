defmodule DawarichWeb.TripsNativeRoutes do
  @moduledoc false

  defmacro trips_native_routes do
    quote do
      live_session :native_trips,
        session: {DawarichWeb.NativeAuth, :live_session, []},
        on_mount: {DawarichWeb.TripsNative.Access, :require_user},
        root_layout: {DawarichWeb.Layouts, :native_root},
        layout: {DawarichWeb.Layouts, :app} do
        live "/trips", DawarichWeb.NativeTripsLive.Index, :index,
          container: {:div, class: "contents"}

        live "/trips/new", DawarichWeb.NativeTripsLive.Form, :new,
          container: {:div, class: "contents"}

        live "/trips/:id/edit", DawarichWeb.NativeTripsLive.Form, :edit,
          container: {:div, class: "contents"}

        live "/trips/:id", DawarichWeb.NativeTripsLive.Show, :show,
          container: {:div, class: "contents"}
      end
    end
  end
end
