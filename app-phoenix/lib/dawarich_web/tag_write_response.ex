defmodule DawarichWeb.TagWriteResponse do
  @moduledoc false
  import Plug.Conn
  alias Dawarich.Navbar
  alias DawarichWeb.{LayoutAssigns, Layouts, Locale, RailsSession, RequestURL, Translate}
  alias DawarichWeb.TagsLive.Form

  def prepare(conn, action, outcome, ctx) do
    case outcome do
      {:ok, _result} -> redirect(conn, action, ctx.locale)
      {:invalid, invalid} -> form(conn, invalid, ctx)
    end
  rescue
    _ in [RailsSession.Overflow, KeyError, ArgumentError] -> :rails
  end

  def send(%{conn: conn, status: status, body: body}),
    do: conn |> send_resp(status, body) |> halt()

  defp redirect(conn, action, locale) do
    kind = %{tag_create: "created", tag_update: "updated", tag_destroy: "deleted"}[action]
    notice = Translate.t(locale, "controllers.tags.tag_was_successfully_#{kind}", %{})

    conn =
      conn
      |> RailsSession.put(%{"flash" => %{"discard" => [], "flashes" => %{"notice" => notice}}})
      |> put_resp_header("location", RequestURL.base(conn) <> "/tags")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_content_type("text/html")

    {:ok, %{conn: conn, status: if(action == :tag_destroy, do: 303, else: 302), body: ""}}
  end

  defp form(conn, invalid, ctx) do
    conn = %{conn | params: conn.assigns.api_params}

    conn =
      conn
      |> fetch_query_params()
      |> Locale.call([])
      |> LayoutAssigns.call([])
      |> assign(:now, ctx.now)

    tag = Map.put_new(invalid.tag, :id, nil)
    kind = if tag.id, do: "edit", else: "new"

    assigns =
      Map.merge(conn.assigns, %{
        __changed__: nil,
        flash: %{},
        tag: tag,
        kind: kind,
        page_title: nil,
        tag_title: Translate.t(ctx.locale, "tags.#{kind}.#{kind}_tag", %{}),
        tag_errors: invalid.errors,
        default_emoji: Form.default_emoji(),
        navbar:
          Navbar.load(conn.assigns.current_user,
            now: ctx.now,
            self_hosted: conn.assigns.self_hosted
          )
      })

    body = Form.page(assigns)
    app = Layouts.app(Map.put(assigns, :inner_content, body))
    html = Layouts.root(Map.put(assigns, :inner_content, app)) |> Phoenix.HTML.Safe.to_iodata()
    changes = Map.get(conn.private, :dawarich_rails_session_changes, %{})
    conn = if changes == %{}, do: conn, else: RailsSession.put(conn, changes)
    {:ok, %{conn: put_resp_content_type(conn, "text/html"), status: 422, body: html}}
  end
end
