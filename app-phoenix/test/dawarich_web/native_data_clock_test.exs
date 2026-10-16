defmodule DawarichWeb.NativeDataClockTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.{Repo, Accounts}
  alias Dawarich.Test.{NativeAdminUI, FrameSeeds}
  @endpoint DawarichWeb.Endpoint
  @path "/points?start_at=1704067200&end_at=1704153599"

  setup do
    %{target: user} = NativeAdminUI.setup!()
    old = System.get_env("JWT_SECRET_KEY")
    System.put_env("JWT_SECRET_KEY", "synthetic-clock-upgrade")

    on_exit(fn ->
      if old, do: System.put_env("JWT_SECRET_KEY", old), else: System.delete_env("JWT_SECRET_KEY")
    end)

    System.put_env("SELF_HOSTED", "false")
    now = DateTime.utc_now() |> DateTime.to_naive()
    Repo.query!("UPDATE users SET plan=0 WHERE id=$1", [user.id], log: false)

    Repo.insert_all("families", [
      %{
        id: 138_901,
        name: "Clock",
        creator_id: 10801,
        access_until: NaiveDateTime.add(now, 3600),
        created_at: now,
        updated_at: now
      }
    ])

    FrameSeeds.point!(user.id, 138_901, 1_704_110_400)
    Dawarich.Test.StatsSeeds.stat!(user.id, %{year: 2024, month: 1, distance: 1000})
    %{user: Accounts.get(user.id)}
  end

  test "native family indicators keep separate mobile and desktop sharing states", %{user: user} do
    for sharing <- [true, false] do
      now = DateTime.utc_now()
      data = Dawarich.Navbar.load(user, now: now, self_hosted: true)
      data = Map.put(data, :family, %{available: true, member: true, sharing: sharing})

      html =
        render_component(&DawarichWeb.Navbar.navbar/1,
          current_user: user,
          data: data,
          locale: "en",
          request_path: "/points",
          base_url: "",
          self_hosted: true,
          now: now,
          native: true
        )

      doc = LazyHTML.from_fragment(html)

      expected =
        DawarichWeb.Translate.t(
          "en",
          "families.navbar_indicator.#{if sharing, do: "location_shared", else: "location_not_shared"}",
          %{}
        )

      for id <- ["family-navbar-indicator", "family-navbar-indicator-mobile"] do
        assert Enum.count(LazyHTML.query(doc, "##{id}")) == 1
        assert LazyHTML.attribute(LazyHTML.query(doc, "##{id}"), "data-tip") == [expected]
      end
    end
  end

  defp grant(view, user, path) do
    now = DateTime.utc_now() |> DateTime.to_naive()

    Repo.insert_all("family_memberships", [
      %{id: 138_901, family_id: 138_901, user_id: user.id, created_at: now, updated_at: now}
    ])

    render_patch(view, path)
  end

  defp reload(view, module, params) do
    :sys.replace_state(view.pid, fn state ->
      {:noreply, socket} = module.handle_params(params, "", state.socket)
      %{state | socket: socket}
    end)
  end

  defp expire(view) do
    Repo.query!(
      "UPDATE families SET access_until=$1",
      [DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.to_naive()],
      log: false
    )

    :sys.replace_state(view.pid, fn state ->
      %{
        state
        | socket:
            Phoenix.Component.assign(state.socket, :now, DateTime.add(DateTime.utc_now(), -86400))
      }
    end)
  end

  test "Points reload uses current family expiry rather than the mount clock", %{user: user} do
    {:ok, view, _} = live(NativeAdminUI.conn(user), @path)
    grant(view, user, @path)
    assert has_element?(view, "#point_138901")
    expire(view)

    reload(view, DawarichWeb.PointsLive.Index, %{
      "start_at" => "1704067200",
      "end_at" => "1704153599",
      "order_by" => "asc"
    })

    refute Enum.any?(:sys.get_state(view.pid).socket.assigns.rows, &(&1.id == 138_901))
  end

  test "Points selection re-admits family expiry at the event clock", %{user: user} do
    {:ok, view, _} = live(NativeAdminUI.conn(user), @path)
    grant(view, user, @path)
    assert has_element?(view, "#point_138901")
    expire(view)
    render_click(view, "select_point", %{"id" => "138901"})
    assert :sys.get_state(view.pid).socket.assigns.selected == MapSet.new()
    assert has_element?(view, "[role=alert]")
  end

  test "Stats reload uses current family expiry rather than the mount clock", %{user: user} do
    {:ok, view, _} = live(NativeAdminUI.conn(user), "/insights?year=2024")
    grant(view, user, "/insights?year=2024")
    refute :sys.get_state(view.pid).socket.assigns.data.restricted
    expire(view)
    reload(view, DawarichWeb.InsightsLive.NativePage, %{"year" => "2024", "page" => "1"})
    assert :sys.get_state(view.pid).socket.assigns.data.restricted
  end
end
