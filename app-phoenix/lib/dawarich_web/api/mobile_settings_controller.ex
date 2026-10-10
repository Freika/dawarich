defmodule DawarichWeb.Api.MobileSettingsController do
  @moduledoc false
  @behaviour Plug
  alias Dawarich.Settings.{Api, Mobile}
  alias DawarichWeb.Api.Respond
  def init(action), do: action

  def call(conn, action) do
    user = conn.assigns.api_user
    ctx = Api.context(conn)

    result = fn ->
      case action do
        :show -> Mobile.show(Dawarich.Repo, user, ctx)
        :update -> Mobile.update(Dawarich.Repo, user, conn.assigns.api_params, ctx)
      end
    end

    if action == :update do
      DawarichWeb.Api.WriteResponse.call(conn, result)
    else
      {_, status, body} = result.()
      Respond.json(conn, status, body)
    end
  rescue
    _ -> Respond.json(conn, 500, Api.failure())
  end
end
