defmodule DawarichWeb.ExportsCreate do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  require Logger

  alias Dawarich.{Exports, PointExports, Repo}
  alias DawarichWeb.{Locale, RailsSession, RequestURL, Translate}
  alias DawarichWeb.Api.Body

  @notice "controllers.exports.export_was_successfully_initiated_please_wait_until_it_s_finished"

  @impl true
  def init(action), do: action

  @impl true
  def call(conn, :decode) do
    case DawarichWeb.A8FormDecode.params(conn, ["file_format[]", "start_at[]", "end_at[]"]) do
      {:ok, conn, params} ->
        query = DawarichWeb.A8FormDecode.urlencoded(conn.query_string)
        conn |> assign(:api_query, query) |> assign(:api_params, Map.merge(params, query))

      {:replay, conn} ->
        Body.replay(conn, "export request envelope")

      {:error, conn} ->
        halt(conn)
    end
  end

  def call(conn, :create) do
    started = System.monotonic_time()
    user = conn.assigns.current_user
    locale = Locale.resolve(nil, user, conn.assigns.rails_session)
    native = native?()

    parsed =
      if native,
        do: Exports.parse_submission(conn.assigns.api_params),
        else: PointExports.parse(conn.assigns.api_params)

    with {:ok, export} <- parsed,
         {:ok, _id} <- PointExports.create(export, user, locale) do
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
      {:error, reason} -> if native, do: failure(conn, locale), else: Body.replay(conn, reason)
    end
  end

  defp native? do
    Dawarich.Standalone.enabled?() or
      Repo.query!("SELECT owner FROM phoenix.job_owners WHERE key='command:exports.points'", [],
        log: false
      ).rows == [["oban"]]
  end

  defp failure(conn, locale) do
    message =
      Translate.t(locale, "controllers.exports.export_failed_to_initiate_please_try_again", %{})

    conn
    |> RailsSession.put(%{"flash" => %{"discard" => [], "flashes" => %{"alert" => message}}})
    |> put_resp_header("location", RequestURL.base(conn) <> "/exports")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_content_type("text/html")
    |> send_resp(422, "")
    |> halt()
  end

  defp log(conn, started) do
    ms = System.convert_time_unit(System.monotonic_time() - started, :native, :millisecond)
    Logger.info("[form] POST /exports 302 #{ms}ms")
    conn
  end
end
