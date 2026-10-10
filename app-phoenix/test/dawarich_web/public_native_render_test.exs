defmodule DawarichWeb.PublicNativeRenderTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.{Repo, SharedLinks}
  alias Dawarich.Sharing.Public
  alias Dawarich.Test.{SharingSeeds, TripsSeeds}
  @endpoint DawarichWeb.Endpoint
  @live "a9500000-0000-4000-8000-000000000001"
  @trip "ac900000-0000-4000-8000-000000000001"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    SharingSeeds.load!()
    now = DateTime.utc_now()

    TripsSeeds.point!(%{
      id: 189_001,
      user_id: 9901,
      timestamp: DateTime.to_unix(now),
      at: [12.5, 51.5]
    })

    TripsSeeds.trip!(%{id: 189_001, user_id: 9901, name: "Native trip"})
    TripsSeeds.shared_link!(%{id: @trip, user_id: 9901, resource_type: 0, trip_id: 189_001})

    Repo.query!(
      "INSERT INTO action_text_rich_texts(record_type,record_id,name,body,created_at,updated_at) VALUES('Trip',189001,'description','<p>Safe notes</p><script>bad()</script>',NOW(),NOW())",
      [],
      log: false
    )

    %{now: now}
  end

  defp read(id, now) do
    {:ok, grant} = Public.grant(SharedLinks.active(id, now), nil, now, DateTime.add(now, 1800))
    Public.read(grant, now)
  end

  defp open(id) do
    conn = get(build_conn(), "/s/" <> id)
    assert conn.status == 200
    result = live(put_private(conn, :live_view_connect_info, %{session: get_session(conn)}))
    assert elem(result, 0) == :ok
    {:ok, view, html} = result
    {view, html}
  end

  test "public optional sections route and gallery reflect only authorized settings", c do
    {:ok, page} = read(@live, c.now)
    assert page.map.latest == [[12.5, 51.5, DateTime.to_unix(c.now)]]
    assert page.map.points == page.map.latest

    Repo.query!(
      "UPDATE shared_links SET settings=$2 WHERE id=$1::text::uuid",
      [@live, %{"show_route" => false}],
      log: false
    )

    {:ok, page} = read(@live, c.now)
    assert page.map.points == []
    assert page.map.latest != []

    for enabled <- [true, false] do
      Repo.query!(
        "UPDATE shared_links SET settings=$2 WHERE id=$1::text::uuid",
        [
          @trip,
          %{
            "show_route" => enabled,
            "show_stats" => enabled,
            "show_days" => enabled,
            "show_description" => enabled,
            "show_photos" => enabled
          }
        ],
        log: false
      )

      {view, html} = open(@trip)
      assert has_element?(view, "[data-public-map]") == enabled
      assert has_element?(view, "[data-public-replay-panel]") == enabled

      if enabled,
        do: assert(has_element?(view, "[data-public-replay-action=replayScrubberHover]"))

      assert has_element?(view, "[data-public-stats]") == enabled
      assert has_element?(view, "[data-public-days]") == enabled
      assert has_element?(view, "[data-public-description]") == enabled
      if enabled, do: assert(html =~ "Safe notes")

      assert html
             |> LazyHTML.from_document()
             |> LazyHTML.query("[data-public-description] script")
             |> Enum.empty?()

      refute html =~ "data-controller"
      if !enabled, do: assert(:sys.get_state(view.pid).socket.assigns.page.map.photos == [])
    end
  end

  test "public snapshots recheck privacy and refuse queued coordinates after revocation", c do
    {view, html} = open(@live)
    refute html =~ "data-latitude"

    assert :sys.get_state(view.pid).socket.assigns.page.map.latest == [
             [12.5, 51.5, DateTime.to_unix(c.now)]
           ]

    Repo.query!(
      "INSERT INTO places(id,user_id,name,latitude,longitude,lonlat,created_at,updated_at) VALUES(189001,9901,'Synthetic private',51.5,12.5,ST_SetSRID(ST_MakePoint(12.5,51.5),4326)::geography,NOW(),NOW())",
      [],
      log: false
    )

    Repo.query!(
      "INSERT INTO tags(id,user_id,name,privacy_radius_meters,created_at,updated_at) VALUES(189001,9901,'Synthetic private',500,NOW(),NOW())",
      [],
      log: false
    )

    Repo.query!(
      "INSERT INTO taggings(tag_id,taggable_type,taggable_id,created_at,updated_at) VALUES(189001,'Place',189001,NOW(),NOW())",
      [],
      log: false
    )

    render_click(view, "public_reload", %{})
    state = :sys.get_state(view.pid).socket.assigns
    assert state.page.map.latest == []
    assert state.page.map.points == []

    Repo.query!("UPDATE shared_links SET revoked_at=NOW() WHERE id=$1::text::uuid", [@live],
      log: false
    )

    send(view.pid, {:share_changed, @live, %{latitude: 51.5, longitude: 12.5}})
    render(view)
    assert :sys.get_state(view.pid).socket.assigns.page == nil
    assert_push_event(view, "public-share-clear", %{})
    assert {:error, _} = read_revoked(c.now)
  end

  test "native shared track honors the disabled route section" do
    id = "ac900000-0000-4000-8000-000000000005"

    Repo.query!(
      "INSERT INTO tracks(id,user_id,start_at,end_at,distance,duration,original_path,created_at,updated_at) VALUES(189005,9901,NOW()-interval '1 hour',NOW(),1000,3600,ST_GeomFromText('LINESTRING(12.5 51.5,12.6 51.6)',4326),NOW(),NOW())",
      [],
      log: false
    )

    TripsSeeds.shared_link!(%{id: id, user_id: 9901, resource_type: 1, trip_id: 189_005})

    for enabled <- [true, false] do
      Repo.query!(
        "UPDATE shared_links SET settings=$2 WHERE id=$1::text::uuid",
        [id, %{"show_route" => enabled}],
        log: false
      )

      {view, _} = open(id)
      assert has_element?(view, "[data-public-map]") == enabled
      if !enabled, do: assert(:sys.get_state(view.pid).socket.assigns.page.map.points == [])
    end
  end

  test "silent live-point age erases its marker without another publication", c do
    {view, _} = open(@live)
    assigns = :sys.get_state(view.pid).socket.assigns
    assert assigns.public_expiry.due == DateTime.to_unix(c.now) + 901

    Repo.query!(
      "UPDATE points SET timestamp=$1 WHERE user_id=9901",
      [DateTime.to_unix(c.now) - 901],
      log: false
    )

    send(view.pid, {:public_share_expiry, assigns.public_expiry.token})
    render(view)
    page = :sys.get_state(view.pid).socket.assigns.page
    assert page.map.latest == []
    assert page.expires_at > assigns.public_expiry.due
  end

  for change <- [:link, :privacy] do
    @change change
    test "native public snapshots reject #{@change} changes during an in-flight read", c do
      link = SharedLinks.active(@live, c.now)
      {:ok, grant} = Public.grant(link, nil, c.now, DateTime.add(c.now, 1800))
      parent = self()
      handler = {__MODULE__, parent}

      :ok =
        :telemetry.attach(
          handler,
          [:dawarich, :repo, :query],
          fn _, _, metadata, _ ->
            if Process.get(:public_snapshot_probe) == parent and
                 String.contains?(metadata.query, "sampled") do
              Process.delete(:public_snapshot_probe)
              send(parent, {:public_snapshot_paused, self()})

              receive do
                :continue_snapshot -> :ok
              after
                5000 -> :ok
              end
            end
          end,
          nil
        )

      on_exit(fn -> :telemetry.detach(handler) end)

      task =
        Task.async(fn ->
          receive do
            :read_snapshot -> :ok
          end

          Process.put(:public_snapshot_probe, parent)
          Public.read(grant, c.now)
        end)

      :ok = Ecto.Adapters.SQL.Sandbox.allow(Repo, parent, task.pid)
      send(task.pid, :read_snapshot)
      assert_receive {:public_snapshot_paused, reader}, 5000

      if @change == :link do
        Repo.query!("UPDATE shared_links SET revoked_at=NOW() WHERE id=$1::text::uuid", [@live],
          log: false
        )
      else
        Repo.query!(
          "INSERT INTO places(id,user_id,name,latitude,longitude,lonlat,created_at,updated_at) VALUES(189004,9901,'Synthetic private',51.5,12.5,ST_SetSRID(ST_MakePoint(12.5,51.5),4326)::geography,NOW(),NOW())",
          [],
          log: false
        )

        Repo.query!(
          "INSERT INTO tags(id,user_id,name,privacy_radius_meters,created_at,updated_at) VALUES(189004,9901,'Synthetic private',500,NOW(),NOW())",
          [],
          log: false
        )

        Repo.query!(
          "INSERT INTO taggings(tag_id,taggable_type,taggable_id,created_at,updated_at) VALUES(189004,'Place',189004,NOW(),NOW())",
          [],
          log: false
        )
      end

      send(reader, :continue_snapshot)
      assert {:error, _} = Task.await(task, 5000)
    end
  end

  defp read_revoked(now),
    do:
      Public.read(
        %{id: @live, version: "stale", viewer: nil, expires_at: DateTime.to_unix(now) + 1800},
        now
      )
end
