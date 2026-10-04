defmodule DawarichWeb.SegmentWriteResponse do
  @moduledoc false
  use DawarichWeb, :html
  import Plug.Conn
  alias Dawarich.TrackSegments.DisplayLegs
  alias DawarichWeb.{Chrome, SegmentFrame, SegmentLegs, SegmentRow, Translate, RailsSession}

  def prepare(conn, outcome, ctx) do
    if conn.assigns.map_write_format == :turbo_stream do
      case render(outcome, ctx) do
        {:ok, response} ->
          conn =
            conn
            |> put_resp_content_type(response.content_type)
            |> put_resp_header("vary", response.vary)

          {:ok, Map.put(response, :conn, conn)}

        :rails ->
          :rails
      end
    else
      kind = if elem(outcome, 0) == :ok, do: "notice", else: "alert"

      conn =
        conn
        |> RailsSession.put(%{
          "flash" => %{"discard" => [], "flashes" => %{kind => message(outcome, ctx.locale)}}
        })
        |> put_resp_header("location", ctx.location)
        |> put_resp_header("cache-control", "no-cache")
        |> put_resp_content_type("text/html")

      {:ok, %{conn: conn, status: 302, body: ""}}
    end
  rescue
    _ in [RailsSession.Overflow, KeyError, ArgumentError] -> :rails
  end

  def send(%{conn: conn, status: status, body: body}),
    do: conn |> send_resp(status, body) |> halt()

  def render(outcome, ctx) do
    {status, streams} = streams(outcome, ctx)

    {:ok,
     %{status: status, body: streams, content_type: "text/vnd.turbo-stream.html", vary: "Accept"}}
  rescue
    _ in [KeyError, ArgumentError] -> :rails
  end

  def message({:ok, _}, locale),
    do: Translate.t(locale, "controllers.tracks.segments.segment_updated", %{})

  def message({:error, %{error_code: code}}, locale),
    do: Translate.t(locale, "controllers.tracks.segments.#{code}", %{})

  defp streams({:ok, result} = outcome, ctx) do
    assigns = Map.merge(ctx, result.page)

    content =
      if result.reset do
        [
          stream(
            "replace",
            "track-#{result.track.id}-segments",
            component(&SegmentFrame.frame/1, assigns)
          )
        ]
      else
        row =
          stream(
            "replace",
            "segment-row-#{result.segment.id}",
            component(&SegmentRow.row/1, Map.put(assigns, :segment, result.segment))
          )

        case DisplayLegs.call(result.page.segments) do
          nil ->
            [row]

          display ->
            [
              row,
              stream(
                "replace",
                "track-#{result.track.id}-legs",
                component(&SegmentLegs.legs/1, Map.put(assigns, :display, display))
              )
            ]
        end
      end

    label =
      Translate.t(
        ctx.locale,
        "transportation_modes.#{result.track.dominant_mode || "unknown"}",
        %{}
      )

    {200,
     content ++
       [
         stream("update", "track-info-mode-#{result.track.id}", Phoenix.HTML.html_escape(label)),
         flash("success", message(outcome, ctx.locale), ctx.locale)
       ]}
  end

  defp streams({:error, _} = outcome, ctx),
    do: {422, [flash("error", message(outcome, ctx.locale), ctx.locale)]}

  defp flash(type, message, locale),
    do:
      stream(
        "append",
        "flash-messages",
        component(&Chrome.flash_message/1, %{type: type, message: message, locale: locale})
      )

  defp component(fun, assigns), do: assigns |> Map.put(:__changed__, nil) |> fun.()

  defp stream(action, target, content) do
    assigns = %{__changed__: nil, action: action, target: target, content: content}

    ~H"""
    <turbo-stream action={@action} target={@target}><template>{@content}</template></turbo-stream>
    """
    |> Phoenix.HTML.Safe.to_iodata()
  end
end
