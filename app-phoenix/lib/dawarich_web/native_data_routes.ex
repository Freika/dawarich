defmodule DawarichWeb.NativeDataRoutes do
  @moduledoc false
  defmacro native_data_routes do
    quote do
      scope "/" do
        pipe_through [:browser, :rails_user]

        live_session :native_data,
          session: {DawarichWeb.NativeAuth, :live_session, []},
          on_mount: {DawarichWeb.NativeDataAuth, :require_user},
          root_layout: {DawarichWeb.Layouts, :native_root},
          layout: {DawarichWeb.Layouts, :app} do
          live "/stats", DawarichWeb.StatsLive.NativePage, :index,
            container: {:div, class: "contents"}

          live "/stats/:year", DawarichWeb.StatsLive.NativePage, :year,
            container: {:div, class: "contents"}

          live "/insights", DawarichWeb.InsightsLive.NativePage, :index,
            container: {:div, class: "contents"}

          live "/insights/details", DawarichWeb.InsightsLive.NativePage, :details,
            container: {:div, class: "contents"}

          live "/digests", DawarichWeb.DigestsLive.NativePage, :index,
            container: {:div, class: "contents"}

          live "/digests/:year", DawarichWeb.DigestsLive.NativePage, :show,
            container: {:div, class: "contents"}

          live "/achievements", DawarichWeb.NativeAchievementsLive, :index,
            container: {:div, class: "contents"}

          live "/achievements/:key", DawarichWeb.NativeAchievementsLive, :show,
            container: {:div, class: "contents"}

          live "/points", DawarichWeb.PointsLive.Index, :index,
            container: {:div, class: "contents"}
        end
      end
    end
  end
end
