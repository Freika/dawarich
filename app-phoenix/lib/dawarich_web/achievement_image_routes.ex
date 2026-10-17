defmodule DawarichWeb.AchievementImageRoutes do
  @moduledoc false
  defmacro achievement_image_routes do
    quote do
      pipeline :achievement_image do
        plug DawarichWeb.HostAuthorization
        plug DawarichWeb.ForceSSL
        plug DawarichWeb.RateLimit
        plug DawarichWeb.RailsAuth
      end

      scope "/" do
        pipe_through :achievement_image

        get "/shared/achievements/:uuid/og.png", DawarichWeb.AchievementPublicImage, []
      end
    end
  end
end
