defmodule DawarichWeb.SegmentWriteResponse do
  @moduledoc false
  use DawarichWeb, :html
  alias Dawarich.TrackSegments.DisplayLegs
  alias DawarichWeb.{Chrome, SegmentFrame, SegmentLegs, SegmentRow, Translate}

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
