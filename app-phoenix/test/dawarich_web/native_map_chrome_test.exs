defmodule DawarichWeb.NativeMapChromeTest do
  use Dawarich.DataCase, async: true
  import Phoenix.LiveViewTest
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint

  defmodule Host do
    use DawarichWeb, :live_view

    def mount(_, %{"user_id" => id}, socket) do
      user = Dawarich.Accounts.get(id)

      {:ok,
       socket
       |> assign(
         current_scope: Dawarich.Maps.principal(user, "en"),
         current_user: user,
         now: DateTime.utc_now(),
         self_hosted: true,
         page: %{},
         locale: "en",
         request_path: "/map/v2",
         base_url: "http://localhost"
       )
       |> DawarichWeb.NativeMapChrome.load()}
    end

    def render(assigns) do
      ~H"""
      <DawarichWeb.NativeMapChrome.header {assigns} />
      """
    end
  end

  test "declining changelog consent removes the map prompt immediately and after reconnect" do
    id = System.unique_integer([:positive])
    RailsUser.insert!(%{id: id, email: "chrome-#{id}@example.invalid"})
    session = %{"user_id" => id}
    {:ok, view, html} = live_isolated(Phoenix.ConnTest.build_conn(), Host, session: session)
    assert html =~ "Stay up to date?"

    view
    |> element("form[action='/settings/changelog_consent']", "No thanks")
    |> render_submit(%{"decision" => "declined"})

    refute has_element?(view, "h3", "Stay up to date?")
    assert rows("SELECT changelog_consent FROM users WHERE id=$1", [id]) == [[0]]

    {:ok, _view, reconnected} =
      live_isolated(Phoenix.ConnTest.build_conn(), Host, session: session)

    refute reconnected =~ "Stay up to date?"
  end
end
