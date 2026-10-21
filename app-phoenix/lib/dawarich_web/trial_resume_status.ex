defmodule DawarichWeb.TrialResumeStatus do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias DawarichWeb.RequestURL

  def init(opts), do: opts
  def call(%{halted: true} = conn, _opts), do: conn

  def call(%{assigns: %{current_user: %{status: 3}}} = conn, _opts) do
    conn = DawarichWeb.TrialHomeSession.call(conn, [])

    if Dawarich.Standalone.enabled?() and not DawarichWeb.TrialGate.checkout_configured?() do
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("pragma", "no-cache")
      |> DawarichWeb.StandaloneError.respond("checkout_unavailable", 503)
    else
      conn
    end
  end

  def call(conn, _opts) do
    conn = DawarichWeb.TrialHomeSession.call(conn, [])

    conn
    |> put_resp_header("location", RequestURL.base(conn) <> "/")
    |> put_resp_content_type("text/html")
    |> send_resp(302, "")
    |> halt()
  end
end
