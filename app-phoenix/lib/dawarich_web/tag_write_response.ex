defmodule DawarichWeb.TagWriteResponse do
  @moduledoc false
  import Plug.Conn
  alias DawarichWeb.{RailsSession, RequestURL, Translate}

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

  defp form(_conn, _invalid, _ctx), do: :rails
end
