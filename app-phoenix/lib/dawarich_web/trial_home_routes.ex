defmodule DawarichWeb.TrialHomeRoutes do
  @moduledoc false
  defmacro trial_home_routes do
    quote do
      scope "/" do
        pipe_through :public_home

        get "/", DawarichWeb.HomeDispatch, []
      end

      scope "/" do
        pipe_through :trial_welcome

        get "/trial/welcome", DawarichWeb.TrialWelcome, []
      end

      scope "/" do
        pipe_through :rails_frame

        get "/trial/upgrade", DawarichWeb.TrialUpgrade, []
      end

      scope "/" do
        pipe_through :trial_resume

        live_session :trial_resume,
          session: {DawarichWeb.RailsAuth, :live_session, []},
          on_mount: DawarichWeb.TrialLiveAuth,
          root_layout: {DawarichWeb.Layouts, :root},
          layout: {DawarichWeb.Layouts, :app} do
          live "/trial/resume", DawarichWeb.TrialLive.Resume, :show,
            container: {:div, class: "contents"}
        end
      end
    end
  end
end
