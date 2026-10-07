defmodule DawarichWeb.Api.DigestWritesController do
  @moduledoc false
  @behaviour Plug
  alias Dawarich.{Repo, Digests.HttpWrites}
  alias DawarichWeb.Api.{Respond, WriteResponse}

  def init(action), do: action

  def call(conn, :create) do
    WriteResponse.call(conn, fn ->
      HttpWrites.create(
        Repo,
        conn.assigns.api_user,
        conn.assigns.api_params["year"],
        Dawarich.Settings.Api.context(conn)
      )
    end)
  rescue
    _ -> Respond.json(conn, 500, Dawarich.Settings.Api.failure())
  end

  def call(conn, :destroy) do
    WriteResponse.call(conn, fn ->
      HttpWrites.destroy(Repo, conn.assigns.api_user, conn.path_params["year"])
    end)
  rescue
    _ -> Respond.json(conn, 500, Dawarich.Settings.Api.failure())
  end
end
