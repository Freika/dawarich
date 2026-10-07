defmodule DawarichWeb.TrialHomeRoutes do
  @moduledoc false
  defmacro trial_home_routes do
    quote do
      scope "/" do
        pipe_through :public_home

        get "/", DawarichWeb.HomeDispatch, [],
          metadata: %{rails_gate: {DawarichWeb.HomeGate, :owned?}}
      end

      scope "/" do
        pipe_through :trial_welcome

        get "/trial/welcome", DawarichWeb.TrialWelcome, [],
          metadata: %{rails_gate: {DawarichWeb.WelcomeGate, :owned?}}
      end

      scope "/" do
        pipe_through :rails_frame

        get "/trial/upgrade", DawarichWeb.TrialUpgrade, [],
          metadata: %{rails_gate: {DawarichWeb.TrialGate, :upgrade?}}
      end

      scope "/" do
        pipe_through :trial_resume

        live_session :trial_resume,
          session: {DawarichWeb.RailsAuth, :live_session, []},
          on_mount: DawarichWeb.TrialLiveAuth,
          root_layout: {DawarichWeb.Layouts, :root},
          layout: {DawarichWeb.Layouts, :app} do
          live "/trial/resume", DawarichWeb.TrialLive.Resume, :show,
            container: {:div, class: "contents"},
            metadata: %{rails_gate: {DawarichWeb.TrialGate, :resume?}}
        end
      end
    end
  end
end
