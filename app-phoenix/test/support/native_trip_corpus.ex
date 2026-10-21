defmodule Dawarich.Test.NativeTripCorpus do
  import ExUnit.Assertions
  import Phoenix.LiveViewTest

  def render(user, id, now) do
    scope = Dawarich.Maps.principal(user, "en")
    assert {:ok, view} = Dawarich.Maps.Trip.view(scope, id, now: now)
    page = view.presentation

    render_component(&DawarichWeb.NativeTripContent.content/1, %{
      page: page,
      locale: "en",
      plan_enabled: view.config["planEnabled"]
    }) <>
      render_component(&DawarichWeb.NativeTripMapPanel.panel/1, %{
        config: view.config,
        locale: "en",
        state: page.map_state,
        has_path: page.has_path,
        future: page.future_start
      }) <>
      render_component(&DawarichWeb.NativeTripActions.actions/1, %{page: page, locale: "en"})
  end

  def assert_values(html, source) do
    assert texts(html, "h1") == texts(source, "h1")

    all = html |> LazyHTML.from_fragment() |> LazyHTML.text() |> normalize()

    for value <- texts(source, "p[class*='text-base-content/60']"),
        do: assert(String.contains?(all, value))

    assert attrs(html, "svg[title]", "title") == attrs(source, "svg[title]", "title")
    assert texts(html, ".whitespace-pre-wrap") == texts(source, ".whitespace-pre-wrap")
    assert texts(html, ".prose") == texts(source, ".prose")

    assert attrs(html, "[data-testid=trip-open-map]", "href") ==
             attrs(source, "[data-testid=trip-open-map]", "href")

    days = attrs(source, "details[data-day-key]", "data-day-key")

    assert attrs(html, "details[id^=native-trip-day-]", "id") ==
             Enum.map(days, &("native-trip-day-" <> &1))

    for day <- days do
      actual = text(html, "#native-trip-day-#{day} summary")

      for value <- texts(source, "details[data-day-key='#{day}'] summary span"), value != "" do
        assert String.contains?(actual, String.replace(value, "· ", "")), day
      end
    end
  end

  def attrs(html, selector, key),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> LazyHTML.attribute(key)

  def texts(html, selector),
    do:
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(selector)
      |> Enum.map(&(&1 |> LazyHTML.text() |> normalize()))

  def text(html, selector), do: html |> texts(selector) |> Enum.join(" ")
  defp normalize(value), do: value |> String.replace(~r/\s+/, " ") |> String.trim()
end
