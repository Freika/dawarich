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
    result =
      if conn.assigns.api_format in [:json, :html, :all],
        do: Payload.read(conn.assigns.api_user.id),
        else: {:replay, "account format"}

    case result do
      {:ok, term} -> Respond.json(conn, 200, term)
      {:replay, reason} -> Body.replay(conn, reason)
    end
  end
end
