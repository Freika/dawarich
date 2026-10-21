defmodule DawarichWeb.NativeDemoLiveTest do
  use Dawarich.DataCase, async: false
  import Phoenix.LiveViewTest
  alias Dawarich.{Accounts, Maps, Onboarding}
  alias Dawarich.Test.{DemoData, RailsUser}
  @endpoint DawarichWeb.Endpoint

  defmodule Host do
    use Phoenix.LiveView

    def mount(_params, session, socket) do
      user = Accounts.get(session["user_id"])
      navbar = Dawarich.Navbar.load(user, now: DateTime.utc_now(), self_hosted: true)

      {:ok,
       assign(socket,
         scope: Maps.principal(user, "en"),
         navbar: navbar,
         loader: session["loader"] && Agent.get(session["loader"], & &1),
         timeout: session["timeout"] || 5_000,
         banner: Map.get(session, "banner", true)
       )}
    end

    def render(assigns) do
      ~H"""
      <.live_component
        module={DawarichWeb.OnboardingLiveComponent}
        id="onboarding"
        scope={@scope}
        navbar={@navbar}
        locale="en"
        base_url="http://localhost"
        rails_csrf_token="token"
        auto_open={false}
        demo_loader={@loader}
        demo_timeout={@timeout}
        banner={@banner}
      />
      """
    end
  end

  setup do
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "demo-live-#{id}@dawarich.test",
      settings: %{"timezone" => "Europe/Berlin"}
    })

    %{id: id, scope: Maps.principal(Accounts.get(id), "en")}
  end

  @now ~U[2026-05-27 22:30:00Z]

  test "demo load completes once and lands on profile yesterday", c do
    loader = fn scope ->
      Onboarding.load_demo(scope, Keyword.put(DemoData.fixtures(), :now, @now))
    end

    view = open(c.id, loader)

    view |> element("#native-demo-load") |> render_click()
    assert has_element?(view, "#native-demo-load[disabled]")
    view |> element("dialog#getting_started") |> render_hook("demo:load", %{})

    {path, _flash} = assert_redirect(view)
    query = path |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    assert %{"date" => "2026-05-27", "panel" => "timeline"} = query
    assert rows("SELECT count(*) FROM imports WHERE user_id=$1 AND demo", [c.id]) == [[1]]
  end

  test "earlier timeout cannot cancel retry", c do
    calls = :counters.new(1, [])
    test_pid = self()

    loader = fn _scope ->
      :counters.add(calls, 1, 1)

      if :counters.get(calls, 1) == 1 do
        send(test_pid, :first_started)
        receive do: (:never -> :ok)
      else
        {:ok, %{result: :created, landing: "/map/v2?panel=timeline&date=2026-05-27"}}
      end
    end

    view = open(c.id, loader, 50)
    view |> element("#native-demo-load") |> render_click()
    assert_receive :first_started
    assert render_async(view, 2_000) =~ "Failed to load demo data. Please try again."
    refute has_element?(view, "#native-demo-load[disabled]")

    view |> element("#native-demo-load") |> render_click()
    {path, _} = assert_redirect(view, 2_000)
    assert path =~ "date=2026-05-27"
    assert :counters.get(calls, 1) == 2
  end

  test "adopted demo trip survives removal", c do
    {:ok, _} = Onboarding.load_demo(c.scope, DemoData.fixtures())
    [[trip]] = rows("SELECT id FROM trips WHERE user_id=$1 AND demo", [c.id])
    rows("UPDATE trips SET demo=false WHERE id=$1", [trip])

    view = open(c.id, nil)
    view |> element("#native-demo-remove") |> render_click()
    assert_redirect(view, "/")
    assert rows("SELECT id FROM trips WHERE user_id=$1", [c.id]) == [[trip]]
    assert rows("SELECT count(*) FROM imports WHERE user_id=$1 AND demo", [c.id]) == [[0]]
  end

  test "demo removal carries the localized success notice to its destination", c do
    {:ok, _} = Onboarding.load_demo(c.scope, DemoData.fixtures())
    view = open(c.id, nil)
    view |> element("#native-demo-remove") |> render_click()
    {"/", flash} = assert_redirect(view)
    assert flash["notice"] == "Demo data removed."
  end

  test "the demo banner keeps the Rails single-line layout", c do
    {:ok, _} = Onboarding.load_demo(c.scope, DemoData.fixtures())
    view = open(c.id, nil)

    assert has_element?(
             view,
             ~s|#demo-data-banner[class="fixed bottom-0 left-1/2 -translate-x-1/2 z-30 mb-[calc(1rem+env(safe-area-inset-bottom))]"]|
           )

    assert has_element?(
             view,
             ~s|#demo-data-banner > div[class="alert alert-info shadow-lg py-1.5 px-3 flex items-center gap-1.5 rounded-lg whitespace-nowrap text-sm"]|
           )
  end

  test "the demo banner stays on the map page like the Rails map layout", c do
    {:ok, _} = Onboarding.load_demo(c.scope, DemoData.fixtures())
    assert has_element?(open(c.id, nil), "#demo-data-banner")
    refute has_element?(open(c.id, nil, 5_000, false), "#demo-data-banner")
    assert has_element?(open(c.id, nil, 5_000, false), "#native-demo-load[disabled]")
  end

  test "reconnect reconciles committed demo state", c do
    view = open(c.id, nil)
    refute has_element?(view, "#demo-data-banner")
    refute has_element?(view, "#native-demo-load[disabled]")

    {:ok, _} = Onboarding.load_demo(c.scope, DemoData.fixtures())
    reconnected = open(c.id, nil)
    assert has_element?(reconnected, "#demo-data-banner")
    assert has_element?(reconnected, "#native-demo-load[disabled]")
  end

  defp open(id, loader, timeout \\ 5_000, banner \\ true) do
    loader = loader && start_supervised!({Agent, fn -> loader end}, id: make_ref())

    {:ok, view, _} =
      live_isolated(Phoenix.ConnTest.build_conn(), Host,
        session: %{"user_id" => id, "loader" => loader, "timeout" => timeout, "banner" => banner}
      )

    view
  end
end
