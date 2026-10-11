defmodule DawarichWeb.ExportsCreate do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  require Logger

  alias Dawarich.Exports
  alias Dawarich.Accounts.Scope
  alias DawarichWeb.{Locale, RailsSession, RequestURL, Translate}

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
        refuse(conn)

      {:error, conn} ->
        halt(conn)
    end
  end

  def call(conn, :create) do
    started = System.monotonic_time()
    user = conn.assigns.current_user
    locale = Locale.resolve(nil, user, conn.assigns.rails_session)

    with {:ok, _id} <- Exports.request(Scope.for_user(user, locale), conn.assigns.api_params) do
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
      {:error, _} -> failure(conn, locale)
    end
  end

  def call(conn, :admit) do
    case DawarichWeb.RailsForm.admission(conn) do
      :ok -> conn
      {:replay, _} -> refuse(conn)
    end
  end

  defp refuse(conn) do
    conn
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_content_type("text/html")
    |> log(System.monotonic_time(), 422)
    |> send_resp(422, "")
    |> halt()
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

  defp log(conn, started, status \\ 302) do
    ms = System.convert_time_unit(System.monotonic_time() - started, :native, :millisecond)
    Logger.info("[form] POST /exports #{status} #{ms}ms")
    conn
  end
end
