defmodule DawarichWeb.NativeDataRoutes do
  @moduledoc false
  defmacro native_data_routes do
    quote do
      pipeline :native_data_request do
        plug DawarichWeb.NativeDataRequest
      end

      scope "/" do
        pipe_through [:native_data_request, :browser, :rails_user]

        live_session :native_data,
          session: {DawarichWeb.NativeAuth, :live_session, []},
          on_mount: {DawarichWeb.NativeDataAuth, :require_user},
          root_layout: {DawarichWeb.Layouts, :native_root},
          layout: {DawarichWeb.Layouts, :app} do
          live "/stats", DawarichWeb.StatsLive.NativePage, :index,
            container: {:div, class: "contents"},
            metadata: %{native_page: true}

          live "/stats/:year", DawarichWeb.StatsLive.NativePage, :year,
            container: {:div, class: "contents"},
            metadata: %{native_page: true}

          live "/insights", DawarichWeb.InsightsLive.NativePage, :index,
            container: {:div, class: "contents"},
            metadata: %{native_page: true}

          live "/insights/details", DawarichWeb.InsightsLive.NativePage, :details,
            container: {:div, class: "contents"},
            metadata: %{native_page: true}

          live "/digests", DawarichWeb.DigestsLive.NativePage, :index,
            container: {:div, class: "contents"},
            metadata: %{native_page: true}

          live "/digests/:year", DawarichWeb.DigestsLive.NativePage, :show,
            container: {:div, class: "contents"},
            metadata: %{native_page: true}

          live "/achievements", DawarichWeb.NativeAchievementsLive, :index,
            container: {:div, class: "contents"},
            metadata: %{native_page: true}

          live "/achievements/:key", DawarichWeb.NativeAchievementsLive, :show,
            container: {:div, class: "contents"},
            metadata: %{native_page: true}

          live "/points", DawarichWeb.PointsLive.Index, :index,
            container: {:div, class: "contents"},
            metadata: %{native_page: true}
        end
      end
    end
  end
end
