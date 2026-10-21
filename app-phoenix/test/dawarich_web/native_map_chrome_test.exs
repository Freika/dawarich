defmodule DawarichWeb.NativeMapChromeTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint

  defmodule Host do
    use DawarichWeb, :live_view

    def mount(_, %{"user_id" => id} = session, socket) do
      user = Dawarich.Accounts.get(id)

      {:ok,
       socket
       |> assign(
         native: true,
         current_scope: Dawarich.Maps.principal(user, "en"),
         current_user: user,
         now: DateTime.utc_now(),
         self_hosted: true,
         page: %{},
         locale: "en",
         request_path: "/map/v2",
         base_url: "http://localhost"
       )
       |> then(fn socket ->
         if session["chrome"] == "app" do
           socket
           |> DawarichWeb.NativeMapChrome.refresh()
           |> DawarichWeb.NavbarHooks.attach(params: false)
         else
           DawarichWeb.NativeMapChrome.load(socket)
         end
       end)}
    end

    def handle_event(_, _, socket), do: {:noreply, socket}

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

  test "Rails error flash survives the root redirect and connected native map mount" do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "chrome-error-#{id}@example.invalid",
      settings: %{"timezone" => "UTC"}
    })

    extra = %{
      "flash" => %{
        "discard" => [],
        "flashes" => %{"error" => "You are not authorized to perform this action."}
      }
    }

    conn = RailsUser.signed_in(id, extra) |> RailsUser.connecting_as(id) |> get("/map/v2")
    html = html_response(conn, 200)
    doc = LazyHTML.from_document(html)

    assert doc |> LazyHTML.query("body") |> LazyHTML.attribute("class") == [
             "h-screen !h-[100dvh] overflow-hidden relative"
           ]

    assert doc |> LazyHTML.query("meta[name=viewport]") |> LazyHTML.attribute("content") == [
             "width=device-width,initial-scale=1,viewport-fit=cover"
           ]

    assert doc |> LazyHTML.query("#map-footer.hidden footer") |> Enum.count() == 1
    {:ok, view, _} = live(conn)

    assert has_element?(
             view,
             "#flash-messages [role=alert]",
             "You are not authorized to perform this action."
           )
  end

  @tag timeout: 90_000
  test "unrelated map events never reload shared chrome" do
    id = System.unique_integer([:positive])
    RailsUser.insert!(%{id: id, email: "chrome-idle-#{id}@example.invalid"})

    views =
      for chrome <- ~w(map app) do
        {:ok, view, _} =
          live_isolated(build_conn(), Host, session: %{"user_id" => id, "chrome" => chrome})

        view
      end

    key = {__MODULE__, make_ref()}
    owner = self()
    pids = Enum.map(views, & &1.pid)

    for event <- [[:dawarich, :repo, :query], [:phoenix, :endpoint, :stop]] do
      :telemetry.attach(
        {key, event},
        event,
        fn _, _, _, _ ->
          if self() in pids, do: send(owner, {key, event})
        end,
        nil
      )
    end

    try do
      started = System.monotonic_time(:millisecond)
      Process.send_after(self(), {key, :idle_end}, 60_000)
      assert_receive {^key, :idle_end}, 61_000
      assert System.monotonic_time(:millisecond) - started >= 60_000
      counts = collect(key, %{queries: 0, http: 0})

      IO.puts(
        "D1 60s idle map+app native=#{inspect(counts)} Rails=no polling in notifications controller"
      )

      assert counts == %{queries: 0, http: 0}

      for event <- ~w(map:ready map:failed map:panel map:range map:layer),
          do: render_hook(hd(views), event, %{})

      assert collect(key, %{queries: 0, http: 0}) == %{queries: 0, http: 0}
    after
      for event <- [[:dawarich, :repo, :query], [:phoenix, :endpoint, :stop]],
          do: :telemetry.detach({key, event})
    end
  end

  test "a queued notification burst costs no more queries or HTTP requests than Rails" do
    budget = File.read!("test/fixtures/layout_request_budget.json") |> Jason.decode!()

    for chrome <- ~w(map app) do
      id = System.unique_integer([:positive])
      RailsUser.insert!(%{id: id, email: "chrome-burst-#{id}@example.invalid"})

      {:ok, view, _} =
        live_isolated(build_conn(), Host, session: %{"user_id" => id, "chrome" => chrome})

      now = NaiveDateTime.utc_now()

      Dawarich.Repo.insert_all(
        "notifications",
        for(
          n <- 1..budget["burst"],
          do: %{
            user_id: id,
            title: "Burst #{n}",
            content: "Synthetic",
            kind: 0,
            created_at: now,
            updated_at: now
          }
        )
      )

      key = {__MODULE__, make_ref()}
      owner = self()

      for event <- [[:dawarich, :repo, :query], [:phoenix, :endpoint, :stop]] do
        :telemetry.attach(
          {key, event},
          event,
          fn _, _, _, _ ->
            if self() == view.pid, do: send(owner, {key, event})
          end,
          nil
        )
      end

      try do
        :ok = :sys.suspend(view.pid)
        for _ <- 1..budget["burst"], do: send(view.pid, {:domain_changed, id, :notifications})
        :ok = :sys.resume(view.pid)
        render(view)
        counts = collect(key, %{queries: 0, http: 0})
        IO.puts("D1 #{chrome} burst native=#{inspect(counts)} Rails=#{inspect(budget["rails"])}")
        assert counts.http <= budget["rails"]["http"]
        assert counts.queries <= budget["rails"]["queries"], inspect(counts)
        assert has_element?(view, "#notifications-badge", "12")

        assert Enum.count(
                 view
                 |> render()
                 |> LazyHTML.from_fragment()
                 |> LazyHTML.query("#notifications-list .notification-item")
               ) == 10
      after
        for event <- [[:dawarich, :repo, :query], [:phoenix, :endpoint, :stop]],
            do: :telemetry.detach({key, event})
      end
    end
  end

  defp collect(key, counts) do
    receive do
      {^key, [:dawarich, :repo, :query]} -> collect(key, Map.update!(counts, :queries, &(&1 + 1)))
      {^key, [:phoenix, :endpoint, :stop]} -> collect(key, Map.update!(counts, :http, &(&1 + 1)))
    after
      0 -> counts
    end
  end
end
