defmodule DawarichWeb.Api.RecalculationsController do
  @moduledoc false
  @behaviour Plug
  alias Dawarich.Settings.Api
  alias DawarichWeb.Api.Respond
  def init(action), do: action

  def call(conn, :create) do
    {_, status, body} =
      Dawarich.Users.ApiRecalculation.create(
        Dawarich.Repo,
        conn.assigns.api_user,
        conn.assigns.api_params,
        Api.context(conn)
      )

    Respond.json(conn, status, body)
  rescue
    _ -> Respond.json(conn, 500, Api.failure())
  end
end
