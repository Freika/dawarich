defmodule DawarichWeb.AchievementRoutes do
  @moduledoc false
  defmacro achievement_routes do
    quote do
      pipeline :achievement_action do
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.RailsAuth
        plug DawarichWeb.AchievementActions.Request
        plug DawarichWeb.Locale
        plug DawarichWeb.RailsHeaders
      end

      pipeline :achievement_public do
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.RailsAuth
        plug DawarichWeb.AchievementPublic
      end

      scope "/" do
        pipe_through :achievement_action

        patch "/achievements/:key/toggle_sharing",
              DawarichWeb.AchievementActions.Sharing,
              [action: :sharing],
              metadata: %{rails_gate: {DawarichWeb.AchievementActions.Gate, :sharing?}}

        post "/achievements/:key/toggle_sharing",
             DawarichWeb.AchievementActions.Sharing,
             [action: :sharing],
             metadata: %{rails_gate: {DawarichWeb.AchievementActions.Gate, :sharing?}}

        post "/achievements/unlocks/next",
             DawarichWeb.AchievementActions.Unlocks,
             [action: :next],
             metadata: %{rails_gate: {DawarichWeb.AchievementActions.Gate, :next?}}

        post "/achievements/unlocks/:id/seen",
             DawarichWeb.AchievementActions.Unlocks,
             [action: :seen],
             metadata: %{rails_gate: {DawarichWeb.AchievementActions.Gate, :seen?}}

        post "/achievements/unlocks/dismiss",
             DawarichWeb.AchievementActions.Unlocks,
             [action: :dismiss],
             metadata: %{rails_gate: {DawarichWeb.AchievementActions.Gate, :dismiss?}}
      end

      scope "/" do
        pipe_through :achievement_public

        get "/shared/achievements/:uuid", DawarichWeb.AchievementPublicPage, [],
          metadata: %{
            rails_key: "achievements",
            rails_gate: {DawarichWeb.AchievementPublic, :open?}
          }
      end

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
