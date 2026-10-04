defmodule DawarichWeb.TrialResumeHeaders do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("pragma", "no-cache")
    else
      conn |> put_resp_header("cache-control", "no-cache") |> delete_resp_header("pragma")
    end
  end
end
