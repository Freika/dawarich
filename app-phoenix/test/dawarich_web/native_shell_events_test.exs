defmodule DawarichWeb.NativeShellEventsTest do
  use Dawarich.JobsCase, async: false
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Dawarich.Repo
  alias Dawarich.Test.FrameSeeds
  alias Dawarich.Build.FrontendInventory

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    %{user: Dawarich.Accounts.get(FrameSeeds.user!(8393).id)}
  end

  defp query(html, selector), do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)

  defp notify!(user, title) do
    now = NaiveDateTime.utc_now()

    Repo.insert_all("notifications", [
      %{
        user_id: user.id,
        title: title,
        content: "body",
        kind: 0,
        created_at: now,
        updated_at: now
      }
    ])
  end

  defp navbar(user, extra \\ []) do
    now = DateTime.utc_now()

    render_component(
      &DawarichWeb.Navbar.navbar/1,
      [
        current_user: user,
        data: Dawarich.Navbar.load(user, now: now, self_hosted: true),
        locale: "en",
        request_path: "/tags",
        base_url: "http://localhost",
        self_hosted: true,
        rails_csrf_token: "token",
        now: now,
        native: true
      ] ++ extra
    )
  end

  test "the native achievement host runs the claim protocol through a Phoenix hook", %{user: user} do
    html =
      render_component(&DawarichWeb.Chrome.achievement_host/1, user_id: user.id, native: true)

    host = query(html, "#achievement-unlocks")

    assert LazyHTML.attribute(host, "phx-hook") == ["AchievementUnlocks"]
    assert LazyHTML.attribute(host, "data-next-url") == ["/achievements/unlocks/next"]
    assert LazyHTML.attribute(host, "data-seen-url") == ["/achievements/unlocks/__ID__/seen"]
    assert LazyHTML.attribute(host, "data-dismiss-url") == ["/achievements/unlocks/dismiss"]
    assert LazyHTML.attribute(host, "data-user-id") == [to_string(user.id)]
    refute html =~ "data-controller"
    refute html =~ "data-action"
  end

  test "the native notifications badge counts unread notifications", %{user: user} do
    notify!(user, "First")
    notify!(user, "Second")

    html = navbar(user)

    assert query(html, "#notifications-list") |> LazyHTML.text() =~ "First"
    assert query(html, "#notifications-badge") |> LazyHTML.text() |> String.trim() == "2"
    refute html =~ ~s(data-controller="notifications")
  end

  test "the native family indicator shows the sharing state", %{user: user} do
    for {sharing, text} <- [{true, "location_shared"}, {false, "location_not_shared"}] do
      html =
        render_component(&DawarichWeb.NavbarParts.family_indicator/1,
          locale: "en",
          sharing: sharing,
          native: true
        )

      expected = DawarichWeb.Translate.t("en", "families.navbar_indicator.#{text}", %{})

      assert query(html, "#family-navbar-indicator") |> LazyHTML.attribute("data-tip") == [
               expected
             ]

      refute html =~ "turbo-frame"
    end
  end

  @tag :tmp_dir
  test "the native app shell has no Stimulus or Turbo findings", %{user: user, tmp_dir: dir} do
    html =
      navbar(user) <>
        render_component(&DawarichWeb.Chrome.achievement_host/1, user_id: user.id, native: true)

    File.mkdir_p!(Path.join(dir, "lib"))
    File.write!(Path.join(dir, "lib/shell.heex"), html)

    assert dir |> FrontendInventory.scan() |> Enum.filter(&FrontendInventory.hotwire?/1) == []
  end
end
