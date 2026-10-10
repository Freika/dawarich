defmodule DawarichWeb.TripsNativeRoutes do
  @moduledoc false

  defmacro trips_routes do
    quote do
      scope "/" do
        pipe_through [:browser, :rails_user]

        if Dawarich.NativeM5.MapHosts.ready?(:trips) do
          DawarichWeb.TripsNativeRoutes.trips_native_routes()
        else
          live_session :trips_map_dependency,
            session: {DawarichWeb.NativeAuth, :live_session, []},
            on_mount: DawarichWeb.LiveAuth,
            root_layout: {DawarichWeb.Layouts, :root},
            layout: {DawarichWeb.Layouts, :app} do
            live "/trips", DawarichWeb.TripsLive.Index, :index,
              container: {:div, class: "contents"},
              metadata: %{rails_gate: {DawarichWeb.TripsGate, :index?}}

            live "/trips/new", DawarichWeb.TripsLive.Form, :new,
              container: {:div, class: "contents"},
              metadata: %{rails_gate: {DawarichWeb.TripsGate, :form?}}

            live "/trips/:id/edit", DawarichWeb.TripsLive.Form, :edit,
              container: {:div, class: "contents"},
              metadata: %{rails_gate: {DawarichWeb.TripsGate, :form?}}

            live "/trips/:id", DawarichWeb.TripsLive.Show, :show,
              container: {:div, class: "contents"},
              metadata: %{rails_gate: {DawarichWeb.TripsGate, :show?}}
          end
        end
      end
    end
  end

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
