defmodule DawarichWeb.TripsNativeShowTest do
  use Dawarich.DataCase, async: false

  import Phoenix.LiveViewTest
  import Phoenix.ConnTest, only: [get: 2]

  alias Dawarich.Jobs.Ownership
  alias Dawarich.Test.{NativeAdminUI, TripsNativeUI, TripsSeeds}
  alias DawarichWeb.NativeTripsLive.Show
  alias DawarichWeb.TripsNative.Access

  @endpoint DawarichWeb.Endpoint

  @path [[12.5, 51.25], [12.373468123456789, 51.34]]

  setup do
    previous = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, Dawarich.Repo)
    on_exit(fn -> Application.put_env(:dawarich, :jobs_repo, previous) end)
    Ownership.put!(Repo, "command:trips.calculate", :oban)
    Ownership.put!(Repo, "command:exports.points", :oban)
    TripsSeeds.country!("Germany", "DE", "DEU")
    TripsSeeds.user!(9_961)
    TripsSeeds.user!(9_962)
    :ok
  end

  defp trip!(id, attrs \\ %{}) do
    TripsSeeds.trip!(
      Map.merge(
        %{
          id: id,
          user_id: 9_961,
          path: @path,
          distance: 12_345,
          started_at: ~N[2026-05-09 06:00:00],
          ended_at: ~N[2026-05-12 20:00:00]
        },
        attrs
      )
    )
  end

  defp day_keys(view),
    do:
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-day-key]")
      |> LazyHTML.attribute("data-day-key")

  test "trip initial and connected renders request one calculation for an input revision" do
    id = trip!(996_101, %{distance: nil, path: nil})

    {_, queries} =
      NativeAdminUI.queries(fn ->
        {:ok, view, _html} = TripsNativeUI.live_as(9_961, "/trips/#{id}")
        render_async(view)
        render_patch(view, "/trips/#{id}?from=2026-05-10")
        render_async(view)
      end)

    assert Enum.count(queries, &(&1 =~ "INSERT INTO public.job_outbox")) == 1
    assert rows("SELECT count(*) FROM job_outbox WHERE aggregate_id=$1", [id]) == [[1]]
  end

  test "late day data and old timeout cannot replace the selected trip" do
    first = trip!(996_201)

    second =
      trip!(996_202, %{started_at: ~N[2026-07-01 06:00:00], ended_at: ~N[2026-07-02 20:00:00]})

    {:ok, view, _html} = TripsNativeUI.live_as(9_961, "/trips/#{first}")
    render_async(view)
    assert hd(day_keys(view)) == "2026-05-09"

    session = :trace.session_create(:trips_native_show_runs, self(), [])
    :trace.process(session, view.pid, true, [:call])
    :trace.function(session, {Show, :handle_async, 3}, true, [])
    render_click(view, "retry_days")
    render_async(view)

    assert_receive {:trace, _, :call,
                    {Show, :handle_async, [{:days, _, _, {^first, nil}} = old, _, _]}}

    :trace.session_destroy(session)

    render_patch(view, "/trips/#{second}")
    render_async(view)
    assert day_keys(view) == ~w(2026-07-01 2026-07-02)

    socket = :sys.get_state(view.pid).socket
    {current, pending} = Access.register(socket, :days, {second, nil})
    {:days, generation, ref, fingerprint} = current
    late = %{days: [%{date: ~D[2026-05-09], stats: nil, note: nil}], next: nil}

    for run <- [
          old,
          {:days, generation, make_ref(), fingerprint},
          {:days, generation, ref, {first, nil}},
          {:days, generation - 1, ref, fingerprint}
        ] do
      assert {:noreply, kept} = Show.handle_info({:data_read_timeout, run}, pending)
      assert kept.assigns.days_status == :ready
      assert Access.active?(kept, current)

      assert {:noreply, kept} = Show.handle_async(run, {:ok, {:ok, late}}, pending)
      assert Enum.map(kept.assigns.days, & &1.date) == [~D[2026-07-01], ~D[2026-07-02]]
      assert Access.active?(kept, current)
    end

    assert {:noreply, applied} = Show.handle_async(current, {:ok, {:ok, late}}, pending)
    assert Enum.map(applied.assigns.days, & &1.date) == [~D[2026-05-09]]
    refute Access.active?(applied, current)

    assert {:noreply, timed_out} = Show.handle_info({:data_read_timeout, current}, pending)
    assert timed_out.assigns.days_status == :failed
    assert day_keys(view) == ~w(2026-07-01 2026-07-02)
  end

  test "malformed day window params render the first window" do
    id = trip!(996_211)

    for query <- ["from[]=2026-05-11", "from[a]=1"] do
      {:ok, view, html} = TripsNativeUI.live_as(9_961, "/trips/#{id}?#{query}")
      assert html =~ "trip 996211"
      render_async(view)
      assert day_keys(view) == ~w(2026-05-09 2026-05-10 2026-05-11 2026-05-12)
    end
  end

  test "revoked or deleted trip clears data before update delivery" do
    id = trip!(996_301)
    {:ok, view, _html} = TripsNativeUI.live_as(9_961, "/trips/#{id}")
    render_async(view)

    rows("UPDATE trips SET name='Renamed by worker' WHERE id=$1", [id])
    Dawarich.Trips.Events.broadcast(id)
    assert render(view) =~ "Renamed by worker"

    rows("DELETE FROM trips WHERE id=$1", [id])
    send(view.pid, {:domain_changed, id, :trip})
    assert_redirect(view, "/trips")

    other = trip!(996_302)
    {:ok, view, _html} = TripsNativeUI.live_as(9_961, "/trips/#{other}")
    rows("UPDATE users SET encrypted_password=$1 WHERE id=9961", [String.duplicate("q", 60)])
    send(view.pid, {:domain_changed, other, :trip})
    assert_redirect(view, "/users/sign_in")
  end

  test "a notification sign-out refuses the trip page immediately" do
    id = trip!(996_303)
    {:ok, view, _html} = TripsNativeUI.live_as(9_961, "/trips/#{id}")
    render_async(view)

    send(view.pid, :notification_signed_out)
    assert_redirect(view, "/users/sign_in")
  end

  test "detail shows source values without paths keys or provider settings" do
    rows("UPDATE users SET settings=$1 WHERE id=9961", [
      %{
        "timezone" => "Europe/Berlin",
        "immich_url" => "https://p.invalid",
        "immich_api_key" => "provider-secret"
      }
    ])

    id = trip!(996_401)
    TripsSeeds.rich_text!(id, ~S|<div>Notes <a href="javascript:alert(1)">x</a></div>|)

    TripsSeeds.note!(%{
      id: 996_491,
      trip_id: id,
      user_id: 9_961,
      body: "Lunch by the lake",
      noted_at: ~N[2026-05-10 12:00:00]
    })

    {:ok, view, html} = TripsNativeUI.live_as(9_961, "/trips/#{id}")
    assert html =~ "trip 996401"
    assert html =~ "3 days, 14 hours"
    assert html =~ "12 km"
    assert html =~ "1 country"
    assert html =~ "Notes"
    refute html =~ "javascript:"

    render_async(view)
    assert day_keys(view) == ~w(2026-05-09 2026-05-10 2026-05-11 2026-05-12)
    assert render(view) =~ "Lunch by the lake"

    state = inspect(:sys.get_state(view.pid).socket.assigns, limit: :infinity)

    for secret <- ["provider-secret", "a8-k-9961", "12.37346", "p.invalid"],
        do: refute(state =~ secret)

    refute render(view) =~ "a8-k-9961"
  end

  test "detail renders the rich description without retaining attachment capabilities" do
    TripsSeeds.country!("France", "FR", "FRA")

    [[blob]] =
      rows(
        "INSERT INTO active_storage_blobs(key,filename,content_type,metadata,service_name,byte_size,checksum,created_at) VALUES($1,'plan.txt','text/plain','{}','local',9,'synthetic',now()) RETURNING id",
        [Ecto.UUID.generate()]
      )

    sgid = Dawarich.RailsMessages.attachable_sgid(blob)
    id = trip!(996_411)

    TripsSeeds.rich_text!(
      id,
      ~s(<div>Plan <action-text-attachment sgid="#{sgid}"></action-text-attachment></div>)
    )

    [[rich]] = rows("SELECT id FROM action_text_rich_texts WHERE record_id=$1", [id])

    rows(
      "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('embeds','ActionText::RichText',$1,$2,now())",
      [rich, blob]
    )

    other = trip!(996_412)
    TripsSeeds.rich_text!(other, "<div>Second description</div>")

    {:ok, view, html} = TripsNativeUI.live_as(9_961, "/trips/#{id}")
    assert html =~ sgid
    assert html =~ ~s(title="Germany")
    render_async(view)
    assert render(view) =~ sgid

    state = inspect(:sys.get_state(view.pid).socket, limit: :infinity, printable_limit: :infinity)

    for retained <- [sgid, "plan.txt", "France"],
        do: refute(state =~ retained, "retained detail value")

    render_patch(view, "/trips/#{other}")
    render_async(view)
    assert render(view) =~ "Second description"
    refute render(view) =~ sgid
  end

  test "day details keep their client open state across patches" do
    id = trip!(996_421)
    {:ok, view, _html} = TripsNativeUI.live_as(9_961, "/trips/#{id}")
    render_async(view)

    ops =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("details[data-day-key]")
      |> LazyHTML.attribute("phx-mounted")
      |> Enum.map(&Jason.decode!/1)

    assert length(ops) == 4
    assert Enum.all?(ops, &(["ignore_attrs", %{"attrs" => ["open"]}] in &1))
  end

  test "toolbar events recalculate, export and delete through scoped commands" do
    id = trip!(996_501)
    {:ok, view, _html} = TripsNativeUI.live_as(9_961, "/trips/#{id}")

    assert render_click(view, "recalculate") =~ "Recalculating"
    assert rows("SELECT count(*) FROM job_outbox WHERE aggregate_id=$1", [id]) == [[1]]

    render_click(view, "export", %{"format" => "gpx"})
    assert %{"notice" => exported} = assert_redirect(view, "/exports")
    assert exported =~ "export"
    assert rows("SELECT count(*) FROM exports WHERE user_id=9961") == [[1]]

    {:ok, view, _html} = TripsNativeUI.live_as(9_961, "/trips/#{id}")
    render_click(view, "delete")
    flash = assert_redirect(view, "/trips")
    assert flash["notice"] =~ "destroyed"
    assert rows("SELECT count(*) FROM trips WHERE id=$1", [id]) == [[0]]
  end

  test "trip events on an unavailable detail are ignored" do
    id = trip!(996_611)

    rows("UPDATE users SET settings=$1 WHERE id=9961", [
      %{"maps" => %{"distance_unit" => "parsecs"}}
    ])

    {:ok, view, _html} = TripsNativeUI.live_as(9_961, "/trips/#{id}")
    assert has_element?(view, "[role='alert']")

    for {event, params} <- [
          {"recalculate", %{}},
          {"export", %{"format" => "gpx"}},
          {"delete", %{}},
          {"retry_days", %{}},
          {"note_edit", %{"date" => "2026-05-10"}},
          {"note_save", %{"note" => %{"date" => "2026-05-10", "body" => "x"}}}
        ],
        do: render_click(view, event, params)

    assert Process.alive?(view.pid)
    assert rows("SELECT count(*) FROM trips WHERE id=$1", [id]) == [[1]]
    assert rows("SELECT count(*) FROM job_outbox WHERE aggregate_id=$1", [id]) == [[0]]
  end

  test "a failed day read offers a retry rather than a recalculation" do
    for {locale, label} <- [{"en", "Retry"}, {"de", "Erneut versuchen"}] do
      button =
        render_component(&DawarichWeb.TripsNative.ShowParts.days/1,
          trip: %{id: 1, settings: %{factor: 1, unit: "km"}},
          days: [],
          status: :failed,
          locale: locale
        )
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("[role='alert'] button[phx-click='retry_days']")

      assert LazyHTML.text(button) |> String.trim() == label
    end
  end

  test "foreign trips are not found and a failed day read can retry" do
    foreign = trip!(996_601, %{user_id: 9_962})
    assert TripsNativeUI.not_found?(9_961, "/trips/#{foreign}")

    id = trip!(996_602)
    {:ok, view, _html} = TripsNativeUI.live_as(9_961, "/trips/#{id}")
    render_async(view)
    socket = :sys.get_state(view.pid).socket

    {run, pending} = Access.register(socket, :days, {id, nil})
    assert {:noreply, failed} = Show.handle_async(run, {:exit, :boom}, pending)
    assert failed.assigns.days_status == :failed

    render_click(view, "retry_days")
    render_async(view)
    assert length(day_keys(view)) == 4
    refute has_element?(view, "[data-days-status='failed']")
  end

  test "trip sharing entry uses M4 creation and refuses a revoked sharing session" do
    id = trip!(996_551)
    target = "/trips/#{id}/share_link/new"
    {:ok, view, _html} = TripsNativeUI.live_as(9_961, "/trips/#{id}")
    render_async(view)

    assert [^target] =
             view
             |> render()
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("a[aria-label='Share trip']")
             |> LazyHTML.attribute("href")

    assert rows("SELECT count(*) FROM shared_links WHERE user_id=9961") == [[0]]

    conn =
      Dawarich.Test.RailsUser.signed_in(9_961)
      |> Dawarich.Test.RailsUser.connecting_as(9_961)

    {:ok, sharing, _html} = live(conn, target)

    attrs = %{
      "shared_link" => %{
        "magic_phrase" => "",
        "expires_at" => "",
        "settings" => %{"show_route" => "1"}
      }
    }

    render_submit(sharing, "sharing_create", attrs)

    assert rows("SELECT user_id,resource_type,resource_id FROM shared_links WHERE user_id=9961") ==
             [[9961, 0, id]]

    rows("UPDATE users SET encrypted_password=$1 WHERE id=9961", [
      "synthetic-revoked-sharing-session"
    ])

    render_submit(sharing, "sharing_create", attrs)
    assert_redirect(sharing, "/users/sign_in")
    assert rows("SELECT count(*) FROM shared_links WHERE user_id=9961") == [[1]]
  end
end
