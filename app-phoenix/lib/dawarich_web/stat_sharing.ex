defmodule DawarichWeb.StatSharing do
  @moduledoc false
  @behaviour Plug
  def init(action), do: action

  def call(conn, :update),
    do:
      DawarichWeb.DigestSharing.update(conn, "stats", fn user, attrs, ctx ->
        Dawarich.Stats.Sharing.update(
          Dawarich.Repo,
          user,
          conn.path_params["year"],
          conn.path_params["month"],
          attrs,
          ctx
        )
      end)
end
