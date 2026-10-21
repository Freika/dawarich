defmodule DawarichWeb.Api.DemoDataController do
  @moduledoc false
  @behaviour Plug
  alias Dawarich.{Repo, DemoData.Api}
  alias DawarichWeb.Api.{Respond, WriteResponse}

  def init(action), do: action

  def call(conn, :show) do
    {:ok, status, body} = Api.show(Repo, conn.assigns.api_user)
    Respond.json(conn, status, body)
  end

  def call(conn, action) do
    WriteResponse.call(conn, fn -> apply(Api, action, [Repo, conn.assigns.api_user]) end)
  rescue
    _ -> Respond.json(conn, 500, Dawarich.Settings.Api.failure())
  end
end
