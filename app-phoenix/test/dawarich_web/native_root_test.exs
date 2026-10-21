defmodule DawarichWeb.NativeRootTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias Dawarich.Accounts.Scope

  defp render_root(extra) do
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
