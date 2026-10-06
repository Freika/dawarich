defmodule DawarichWeb.Api.UsersController do
  @moduledoc false
  @behaviour Plug

  alias Dawarich.AccountApi.{Exist, Payload}
  alias DawarichWeb.Api.Respond

  def init(action), do: action

  def call(conn, :exist) do
    conn = DawarichWeb.Api.AccountManager.call(conn, [])

    {:ok, status, term} =
      Exist.authorized(conn.assigns.api_params, conn.assigns.manager_secret_valid)

    Respond.json(conn, status, term)
  end

  def call(conn, :me) do
    now = conn.assigns[:api_now] || DateTime.utc_now()

    result =
      case Dawarich.AccountApi.Closure.pending(conn.assigns.api_user, now) do
        :ok -> Payload.read(conn.assigns.api_user.id, now)
        pending -> pending
      end

    case result do
      {:ok, term} -> Respond.json(conn, 200, term)
      {:ok, status, term} -> Respond.json(conn, status, term)
      _ -> Respond.json(conn, 500, {:object, [{"error", "internal_server_error"}]})
    end
  end
end
