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
            {:error, _} -> rails(conn)
          end

        {:legacy, _} ->
          rails(conn)

        {:error, _} ->
          rails(conn)
      end
    else
      _ -> rails(conn)
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
    <div class="max-w-lg mx-auto py-12" data-testid="import-download-preparing">
      <h1 class="text-2xl font-bold">#{text(locale, "preparing")}</h1>
      <p class="my-4">#{text(locale, "automatic_download")}</p>
      <a class="btn btn-outline" data-turbo="false" href="/imports/#{record.id}/download?original=1">#{text(locale, "original_archive")}</a>
      <a class="btn btn-ghost" href="/imports">#{text(locale, "back")}</a>
    </div>
    """

    assigns =
      Map.merge(conn.assigns, %{
        __changed__: nil,
        flash: %{},
        page_title: nil,
        inner_content: Phoenix.HTML.raw(body),
        navbar:
          Dawarich.Navbar.load(conn.assigns.current_user,
            now: conn.assigns.now,
            self_hosted: conn.assigns.self_hosted
          )
      })

    html =
      DawarichWeb.Layouts.root(%{assigns | inner_content: DawarichWeb.Layouts.app(assigns)})
      |> Phoenix.HTML.Safe.to_iodata()

    conn
    |> put_resp_header("refresh", "3")
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("text/html")
    |> send_resp(202, html)
  end

  defp text(locale, key),
    do:
      DawarichWeb.Translate.t(locale, "imports.download." <> key, %{})
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()

  defp rails(conn) do
    conn
    |> delete_resp_header("x-dawarich-handler")
    |> register_before_send(&put_resp_header(&1, "x-dawarich-handler", "rails-imports"))
    |> DawarichWeb.RailsProxy.call(Application.fetch_env!(:dawarich, :rails_upstream))
    |> halt()
  end
end
