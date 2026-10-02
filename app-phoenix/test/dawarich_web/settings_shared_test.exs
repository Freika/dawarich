defmodule DawarichWeb.SettingsSharedTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Dawarich.Test.ParityHTML
  alias DawarichWeb.{Icon, SettingsParts}

  test "a locale flag carries the caller's class and no title; a country flag keeps its title" do
    html =
      render_component(&Icon.flag/1,
        code: "gb",
        class: "inline-block rounded-sm h-5 w-auto shadow-sm shrink-0"
      )

    assert html =~ ~s(class="inline-block rounded-sm h-5 w-auto shadow-sm shrink-0")
    refute html =~ "title="
    assert render_component(&Icon.flag/1, code: "de", title: "Germany") =~ ~s(title="Germany")
  end

  test "the flag SVG file is read once per code and cached" do
    render_component(&Icon.flag/1, code: "fr", class: "x")
    assert :persistent_term.get({DawarichWeb.Icon, :flag, "fr"})
  end

  test "the tabs: Rails' order, the active tab, 2FA only when configured, admin and self-hosted tabs" do
    tabs = fn assigns ->
      (&SettingsParts.navigation/1)
      |> render_component(Map.merge(%{locale: "en", active: "integrations"}, assigns))
      |> LazyHTML.from_fragment()
    end

    member = tabs.(%{self_hosted: true, admin: false, two_factor: true})

    assert member |> LazyHTML.query("a[role='tab']") |> Enum.map(&LazyHTML.text/1) ==
             ["General", "Integrations", "Visits", "Two-Factor Authentication", "Background Jobs"]

    assert member |> LazyHTML.query("a.tab-active") |> LazyHTML.attribute("href") == [
             "/settings/integrations"
           ]

    assert member
           |> LazyHTML.query(
             "#settings-navigation[phx-hook='RailsStimulus'][data-controller='scroll-into-view']"
           )
           |> Enum.count() == 1

    admin = tabs.(%{self_hosted: true, admin: true, two_factor: false})

    assert admin |> LazyHTML.query("a[role='tab']") |> LazyHTML.attribute("href") ==
             ~w(/settings/general /settings/integrations /settings/visits /settings/users /admin/settings /settings/background_jobs)

    cloud = tabs.(%{self_hosted: false, admin: true, two_factor: false})
    assert cloud |> LazyHTML.query("a[role='tab']") |> Enum.count() == 3
  end

  test "the Stimulus comparator takes the caller's selector" do
    html =
      ~s(<div data-controller="upload" data-upload-url-value="/x"><input data-upload-target="input"></div><a data-turbo-confirm="Sure?" href="/y">y</a>)

    assert ParityHTML.stimulus(
             html,
             "[data-controller], [data-upload-target], [data-turbo-confirm]"
           ) == [
             {"div", [{"data-controller", "upload"}, {"data-upload-url-value", "/x"}]},
             {"input", [{"data-upload-target", "input"}]},
             {"a", [{"data-turbo-confirm", "Sure?"}]}
           ]
  end
end
