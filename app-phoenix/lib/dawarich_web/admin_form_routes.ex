defmodule DawarichWeb.AdminFormRoutes do
  @moduledoc false

  defmacro admin_form_routes do
    quote do
      scope "/" do
        pipe_through :admin_writes

        delete "/settings/users/:id", DawarichWeb.AdminUserDestroy, [],
          metadata: %{rails_gate: {DawarichWeb.AdminWritesGate, :destroy?}}

        post "/admin/settings/test_geocoding",
             DawarichWeb.AdminWrites.Settings,
             [action: :test_geocoding],
             metadata: %{rails_gate: {DawarichWeb.AdminWritesGate, :test_geocoding?}}
      end
    end
  end
end
