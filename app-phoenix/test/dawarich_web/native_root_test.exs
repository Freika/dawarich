defmodule DawarichWeb.NativeRootTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias Dawarich.Accounts.Scope

  defp render_root(extra \\ %{}) do
    %{
      locale: "en",
      current_user: %{id: 1, theme: "dark"},
      self_hosted: true,
      page_title: nil,
      rails_csrf_token: "rails-token",
      inner_content: Phoenix.HTML.raw("<main>page</main>")
    }
    |> Map.merge(extra)
    |> DawarichWeb.Layouts.native_root()
    |> rendered_to_string()
  end

  test "the native root loads only the native bundle" do
    html = render_root()

    assert html =~ ~s(src="/native/app.js")
    assert html =~ "phx-track-static"
    refute html =~ "importmap"
    refute html =~ "/phoenix/js/"
    refute html =~ "turbo"
    refute html =~ "i18n-translations"
    assert html =~ "<main>page</main>"
  end

  test "the native root keeps both CSRF tokens, the theme and the stylesheets" do
    html = render_root()

    assert html =~ ~s(<meta name="csrf-token" content="rails-token">)
    assert html =~ ~s(name="phoenix-csrf-token")
    assert html =~ ~s(data-theme="dawarich-dark")
    assert html =~ "tailwind"
  end

  test "cloud analytics stay on native pages without Turbo tracking" do
    previous = System.get_env("POSTHOG_ENABLED")
    System.put_env("POSTHOG_ENABLED", "true")

    on_exit(fn ->
      if previous,
        do: System.put_env("POSTHOG_ENABLED", previous),
        else: System.delete_env("POSTHOG_ENABLED")
    end)

    html = render_root(%{self_hosted: false})

    assert html =~ "posthog"
    assert html =~ "simpleanalyticscdn"
    refute html =~ "data-turbo-track"
  end

  test "a scope carries the user and the locale" do
    scope = Scope.for_user(%{id: 7}, "de")

    assert scope.user.id == 7
    assert scope.locale == "de"
    assert Scope.for_user(nil, "en") == nil
  end
end
