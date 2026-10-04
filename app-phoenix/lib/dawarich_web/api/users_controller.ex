defmodule DawarichWeb.Api.UsersController do
  @moduledoc false
  @behaviour Plug

  alias Dawarich.AccountApi.Payload
  alias DawarichWeb.Api.{Body, Respond}

  def init(action), do: action

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
