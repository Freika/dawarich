defmodule DawarichWeb.AchievementRoutes do
  @moduledoc false
  defmacro achievement_routes do
    quote do
      pipeline :achievement_initial do
        plug DawarichWeb.AchievementInitial
      end

      scope "/" do
        pipe_through [:browser, :rails_user, :achievement_initial]

        live_session :achievement_pages,
          session: {DawarichWeb.AchievementSession, :live_session, []},
          on_mount: DawarichWeb.LiveAuth,
          root_layout: {DawarichWeb.Layouts, :root},
          layout: {DawarichWeb.Layouts, :app} do
          live "/achievements", DawarichWeb.AchievementsLive, :index,
            container: {:div, class: "contents"},
            metadata: %{rails_gate: {DawarichWeb.AchievementPageGate, :open?}}

          live "/achievements/:key", DawarichWeb.AchievementsLive, :show,
            container: {:div, class: "contents"},
            metadata: %{rails_gate: {DawarichWeb.AchievementPageGate, :open?}}
        end
      end
    end
  end
end
