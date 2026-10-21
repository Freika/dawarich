defmodule DawarichWeb.SegmentWriteResponseTest do
  use ExUnit.Case, async: true
  alias DawarichWeb.SegmentWriteResponse

  defp ctx do
    %{
      user: %{settings: %{"enabled_transportation_modes" => ~w(walking cycling driving)}},
      locale: "en",
      csrf: "CSRF",
      unit: "km",
      now: ~U[2026-10-03 10:00:00Z]
    }
  end

  defp segment(attrs \\ %{}) do
    Map.merge(
      %{
        id: 83601,
        track_id: 8360,
        start_at: ~U[2026-10-03 09:00:00Z],
        end_at: ~U[2026-10-03 09:10:00Z],
        duration: 600,
        distance: 1000,
        transportation_mode: "walking",
        confidence_score: 1.0,
        corrected_at: ~N[2026-10-03 10:00:00]
      },
      attrs
    )
  end

  defp outcome(segment, rows, reset \\ false),
    do:
      {:ok,
       %{
         segment: segment,
         track: %{id: 8360, dominant_mode: "walking"},
         page: %{track_id: 8360, segments: rows},
         reset: reset
       }}

  defp render(outcome) do
    assert {:ok, %{body: body} = response} = SegmentWriteResponse.render(outcome, ctx())
    {response, IO.iodata_to_binary(body)}
  end

  defp targets(html),
    do:
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("turbo-stream")
      |> LazyHTML.attribute("target")

  test "override replaces row optional legs then mode and success flash" do
    {response, html} = render(outcome(segment(), [segment()]))
    assert response.status == 200
    assert response.content_type == "text/vnd.turbo-stream.html"
    assert response.vary == "Accept"

    assert targets(html) == [
             "segment-row-83601",
             "track-8360-legs",
             "track-info-mode-8360",
             "flash-messages"
           ]

    assert html
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("turbo-stream")
           |> LazyHTML.attribute("action") == ["replace", "replace", "update", "append"]

    assert html =~ "Segment updated"

    {_, raw} =
      render(
        outcome(segment(%{start_at: nil, end_at: nil}), [segment(%{start_at: nil, end_at: nil})])
      )

    assert targets(raw) == ["segment-row-83601", "track-info-mode-8360", "flash-messages"]
  end

  test "reset replaces complete list with fresh IDs then mode flash" do
    {response, html} = render(outcome(nil, [segment(%{id: 83602, corrected_at: nil})], true))
    assert response.status == 200
    assert targets(html) == ["track-8360-segments", "track-info-mode-8360", "flash-messages"]
    assert html =~ "segment-row-83602"
    refute html =~ "segment-row-83601"
  end

  test "failure sends only translated 422 error flash" do
    for {code, message} <- [
          {:mode_not_enabled, "That mode isn&#39;t enabled in your settings"},
          {:reprocess_failed, "Re-detection failed — your correction was kept"}
        ] do
      {response, html} = render({:error, %{error_code: code}})
      assert response.status == 422
      assert targets(html) == ["flash-messages"]
      assert html =~ message
      assert html =~ "alert-error"
      refute html =~ "track-info-mode"
    end
  end

  test "raw condensed replacement preserves existing markup and CSRF" do
    for raw <- [false, true] do
      row = if raw, do: segment(%{start_at: nil, end_at: nil}), else: segment()
      {_, html} = render(outcome(row, [row]))

      assert html
             |> String.replace(["<template>", "</template>"], "")
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("input[name='authenticity_token']")
             |> LazyHTML.attribute("value") == List.duplicate("CSRF", if(raw, do: 1, else: 2))

      assert html =~ "track_segment[transportation_mode]"
      assert html =~ "segment-mode-editor"
      assert html =~ "1.0 km"
      assert html =~ "10 min"
    end
  end
end
