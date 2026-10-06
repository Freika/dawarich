defmodule DawarichWeb.ShareManagementOverrideRoutes do
  @moduledoc false

  defmacro routes do
    quote do
      scope "/" do
        pipe_through :share_form

        for {base, type, key} <- [
              {"/share_links/live", "live", nil},
              {"/trips/:trip_id/share_link", "trip", "trip_shares"},
              {"/share_links/shares/:id", "shared", nil}
            ] do
          post base <> "/revoke", DawarichWeb.ShareManagementForm, {type, :revoke},
            metadata: %{
              rails_key: key,
              rails_gate: {DawarichWeb.ShareManagementGate, :mutation?}
            }
        end
      end
    end
  end
end
