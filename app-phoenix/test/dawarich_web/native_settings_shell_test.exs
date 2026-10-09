defmodule DawarichWeb.NativeSettingsShellTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias DawarichWeb.{CoreComponents, SettingsParts}

  defp form(params, errors \\ []),
    do: Phoenix.Component.to_form(params, as: :settings, errors: errors)

  defp query(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)
  defp attr(html, selector, name), do: html |> query(selector) |> LazyHTML.attribute(name)

  test "a checkbox posts false when unchecked and shows its checked state" do
    html =
      render_component(&CoreComponents.input/1,
        field: form(%{"news" => "true"})[:news],
        type: "checkbox",
        label: "News"
      )

    assert attr(html, "input[type=hidden][name='settings[news]']", "value") == ["false"]
    assert attr(html, "input[type=checkbox][name='settings[news]']", "value") == ["true"]
    assert query(html, "input[type=checkbox][checked]") |> Enum.count() == 1
    assert html =~ "News"

    unchecked =
      render_component(&CoreComponents.input/1,
        field: form(%{"news" => "false"})[:news],
        type: "checkbox",
        label: "News"
      )

    assert query(unchecked, "input[type=checkbox][checked]") |> Enum.empty?()
  end

  test "a select marks the current option and keeps option labels" do
    html =
      render_component(&CoreComponents.input/1,
        field: form(%{"timezone" => "Europe/Berlin"})[:timezone],
        type: "select",
        label: "Time zone",
        options: [{"UTC", "UTC"}, {"Berlin", "Europe/Berlin"}]
      )

    assert attr(html, "select[name='settings[timezone]'] option[selected]", "value") == [
             "Europe/Berlin"
           ]

    assert html =~ "Berlin"
  end

  test "a textarea shows its value and errors appear once the field was used" do
    html =
      render_component(&CoreComponents.input/1,
        field: form(%{"note" => "hello"}, note: {"is too long", []})[:note],
        type: "textarea",
        label: "Note"
      )

    assert query(html, "textarea[name='settings[note]']") |> LazyHTML.text() =~ "hello"
    assert html =~ "is too long"

    untouched =
      render_component(&CoreComponents.input/1,
        field: form(%{"note" => "", "_unused_note" => ""}, note: {"is too long", []})[:note],
        type: "textarea",
        label: "Note"
      )

    refute untouched =~ "is too long"
  end

  test "a password field renders only the display value it is given, never the field value" do
    html =
      render_component(&CoreComponents.input/1,
        field: form(%{"api_key" => "raw-secret"})[:api_key],
        type: "password",
        label: "API key",
        display: "********"
      )

    assert attr(html, "input[name='settings[api_key]']", "value") == ["********"]
    refute html =~ "raw-secret"

    blank =
      render_component(&CoreComponents.input/1,
        field: form(%{"api_key" => "raw-secret"})[:api_key],
        type: "password",
        label: "API key"
      )

    refute blank =~ "raw-secret"
  end

  defp navigation(extra),
    do:
      render_component(
        &SettingsParts.navigation/1,
        Map.merge(
          %{locale: "en", active: "visits", self_hosted: true, admin: false, two_factor: false},
          extra
        )
      )

  test "the native settings tabs keep today's tabs and scroll the active one into view" do
    html = navigation(%{native: true})

    assert attr(html, "[role=tab]", "href") == [
             "/settings/general",
             "/settings/integrations",
             "/settings/visits",
             "/settings/background_jobs"
           ]

    assert attr(html, "a.tab-active", "href") == ["/settings/visits"]
    assert attr(html, "#settings-navigation", "phx-hook") == ["ScrollIntoView"]
    refute html =~ "data-controller"
    refute html =~ "RailsStimulus"

    full = navigation(%{native: true, admin: true, two_factor: true})

    assert attr(full, "[role=tab]", "href") == [
             "/settings/general",
             "/settings/integrations",
             "/settings/visits",
             "/settings/two_factor",
             "/settings/users",
             "/admin/settings",
             "/settings/background_jobs"
           ]
  end
end
