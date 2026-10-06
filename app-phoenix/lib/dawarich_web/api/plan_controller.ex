defmodule DawarichWeb.Api.PlanController do
  @moduledoc false
  @behaviour Plug
  alias Dawarich.AccountApi.Closure
  alias DawarichWeb.Api.Respond

  def init(action), do: action

  def call(conn, :show) do
    case Closure.plan(conn.assigns.api_user, conn.assigns[:api_now] || DateTime.utc_now()) do
      {:ok, term} -> Respond.json(conn, 200, term)
      _ -> Respond.json(conn, 500, {:object, [{"error", "internal_server_error"}]})
    end
  end
end
