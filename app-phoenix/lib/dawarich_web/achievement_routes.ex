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
    end
  end
end
