defmodule DawarichWeb.ExportsCreate do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  require Logger

  alias Dawarich.PointExports
  alias DawarichWeb.{Locale, RailsSession, RequestURL, Translate}
  alias DawarichWeb.Api.Body

  @notice "controllers.exports.export_was_successfully_initiated_please_wait_until_it_s_finished"

  @impl true
  def init(action), do: action

  @impl true
  def call(conn, :create) do
    started = System.monotonic_time()
    user = conn.assigns.current_user
    locale = Locale.resolve(nil, user, conn.assigns.rails_session)

    with {:ok, export} <- PointExports.parse(conn.assigns.api_params),
         {:ok, _id} <- PointExports.create(export, user.id, locale) do
      notice = Translate.t(locale, @notice, %{})

      conn
      |> RailsSession.stage(%{"flash" => %{"discard" => [], "flashes" => %{"notice" => notice}}})
      |> put_resp_header("location", RequestURL.base(conn) <> "/exports")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_content_type("text/html")
      |> log(started)
      |> send_resp(302, "")
      |> halt()
    else
      :rails -> Body.replay(conn, "export parameters")
      {:error, reason} -> Body.replay(conn, reason)
    end
  end

  defp log(conn, started) do
    ms = System.convert_time_unit(System.monotonic_time() - started, :native, :millisecond)
    Logger.info("[form] POST /exports 302 #{ms}ms")
    conn
  end
end
