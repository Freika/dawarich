defmodule DawarichWeb.ImportsDownload do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.Imports.{Download, DownloadProducer, UiRecords}
  alias DawarichWeb.ImportsContext
  def init(action), do: action

  def call(conn, :show) do
    conn = put_resp_header(conn, "x-dawarich-handler", "phoenix-imports")
    user = conn.assigns.current_user

    with {:ok, record} <- UiRecords.get(ImportsContext.repo(), user.id, conn.path_params["id"]) do
      context =
        ImportsContext.for_user(user) |> Map.put(:original?, conn.query_params["original"] == "1")

      case Download.with_file(ImportsContext.repo(), user.id, record.id, context, fn path,
                                                                                     name,
                                                                                     type ->
             stream(conn, path, name, type)
           end) do
        {:ok, conn} ->
          conn

        {:error, :pending} ->
          case DownloadProducer.enqueue(
                 ImportsContext.repo(),
                 user.id,
                 record.id,
                 record.source_blob_id,
                 context.now
               ) do
            {:ok, _} -> pending(conn, record, context.locale)
            {:error, _} -> missing(conn)
          end

        {:legacy, _} ->
          conn
          |> delete_resp_header("x-dawarich-handler")
          |> register_before_send(&put_resp_header(&1, "x-dawarich-handler", "rails-imports"))
          |> DawarichWeb.RailsProxy.call(Application.fetch_env!(:dawarich, :rails_upstream))

        {:error, _} ->
          missing(conn)
      end
    else
      _ -> missing(conn)
    end
  end

  defp stream(conn, path, name, type) do
    conn =
      conn
      |> put_resp_content_type(type)
      |> put_resp_header(
        "content-disposition",
        Dawarich.Storage.content_disposition("attachment", name)
      )
      |> send_chunked(200)

    Enum.reduce_while(File.stream!(path, 65_536), conn, fn bytes, current ->
      case chunk(current, bytes) do
        {:ok, current} -> {:cont, current}
        {:error, _} -> {:halt, halt(current)}
      end
    end)
  end

  defp pending(conn, record, locale) do
    body = """
    <div data-testid="native-imports-root" class="max-w-lg mx-auto py-12"><div data-testid="import-download-preparing">
      <h1>#{text(locale, "preparing")}</h1><p>#{text(locale, "automatic_download")}</p>
      <a href="/imports/#{record.id}/download?original=1">#{text(locale, "original_archive")}</a>
      <a href="/imports">#{text(locale, "back")}</a>
    </div></div>
    """

    conn
    |> put_resp_header("refresh", "3")
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("text/html")
    |> send_resp(202, body)
  end

  defp text(locale, key),
    do:
      DawarichWeb.Translate.t(locale, "imports.download." <> key, %{})
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()

  defp missing(conn),
    do:
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(404, Jason.encode!(%{error: "not_found"}))
end
