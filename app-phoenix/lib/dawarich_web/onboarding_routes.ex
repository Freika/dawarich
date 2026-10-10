defmodule DawarichWeb.OnboardingRoutes do
  @moduledoc false
  defmacro onboarding_routes do
    quote do
      scope "/" do
        pipe_through :standalone_settings

        for method <- [:post, :patch, :put] do
          match method, "/settings/onboarding", DawarichWeb.OnboardingActions, :update,
            metadata: %{rails_gate: {DawarichWeb.SettingsActions, :enabled?}}
        end

        for method <- [:post, :delete] do
          match method, "/settings/onboarding/demo_data", DawarichWeb.DemoDataActions, :demo_data,
            metadata: %{rails_gate: {DawarichWeb.SettingsActions, :enabled?}}
        end
      end
    end
  end
end
