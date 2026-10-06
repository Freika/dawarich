defmodule DawarichWeb.Api.UsersController do
  @moduledoc false
  @behaviour Plug

  alias Dawarich.AccountApi.{Exist, Payload}
  alias DawarichWeb.Api.{Auth, Body, Respond}

  def init(action), do: action

  def call(conn, :exist) do
    conn = Auth.public(conn)

    if conn.halted do
      conn
    else
      result =
        if conn.assigns.api_format in [:json, :html, :all],
          do:
            Exist.run(
              conn.assigns.api_params,
              conn |> Plug.Conn.get_req_header("x-webhook-secret") |> Enum.join(", ")
            ),
          else: {:replay, "manager format"}

      case result do
        {:ok, status, term} -> Respond.json(conn, status, term)
        {:replay, reason} -> Body.replay(conn, reason)
      end
    end
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
