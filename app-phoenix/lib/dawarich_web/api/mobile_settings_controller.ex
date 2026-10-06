defmodule DawarichWeb.Api.MobileSettingsController do
  @moduledoc false
  @behaviour Plug
  alias Dawarich.Settings.{Api, Mobile}
  alias DawarichWeb.Api.Respond
  def init(action), do: action

  def call(conn, action) do
    user = conn.assigns.api_user
    ctx = Api.context(conn)

    {_, status, body} =
      case action do
        :show -> Mobile.show(Dawarich.Repo, user, ctx)
        :update -> Mobile.update(Dawarich.Repo, user, conn.assigns.api_params, ctx)
      end

    Respond.json(conn, status, body)
  rescue
    _ -> Respond.json(conn, 500, Api.failure())
  end
end
