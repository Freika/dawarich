defmodule DawarichWeb.NativeTripDeliveryTest do
  use Dawarich.DataCase, async: false
  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest
  alias Dawarich.{Cable.Bus, RailsMessages}
  alias Dawarich.Test.{RailsUser, TripsSeeds}
  @endpoint DawarichWeb.Endpoint

  setup do
    previous = Application.get_env(:dawarich, :cable)
    config = [transport: :redis, bus: true, url: System.fetch_env!("PHOENIX_TEST_REDIS_URL")]
    Application.put_env(:dawarich, :cable, config)
    Enum.each(Bus.child_specs(config), &start_supervised!/1)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:dawarich, :cable, previous),
        else: Application.delete_env(:dawarich, :cable)
    end)

    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "native-trip-delivery-#{id}@dawarich.test",
      settings: %{"timezone" => "UTC"}
    })

    TripsSeeds.trip!(%{
      id: id * 10,
      user_id: id,
      name: "Initial trip",
      started_at: ~N[2026-06-01 12:00:00],
      ended_at: ~N[2026-06-03 12:00:00]
    })

    %{id: id}
  end

  test "native trip delivery refreshes the owning view and refuses a revoked queued event", %{
    id: id
  } do
    {:ok, view, _} = open(id)
    topic = RailsMessages.broadcasting([{:trip, id * 10}])
    state = :sys.get_state(view.pid).socket.assigns[:native_subscriptions]
    assert is_map(state) == true
    assert Map.has_key?(state.topics, topic)

    message =
      {:redix_pubsub, self(), make_ref(), :message,
       %{channel: Bus.channel(topic), payload: "synthetic-trip-update"}}

    Repo.query!("UPDATE trips SET name=$1 WHERE id=$2", ["Updated trip", id * 10], log: false)
    send(view.pid, message)
    assert_push_event(view, "map:invalidate", %{kind: "trip"})
    assert has_element?(view, "#trip-shell h1", "Updated trip")
    assert :sys.get_state(view.pid).socket.assigns.page_title == "Updated trip"
    Repo.query!("DELETE FROM trips WHERE id=$1", [id * 10], log: false)
    send(view.pid, message)
    refute has_element?(view, "#trip-shell")
    assert_push_event(view, "map:clear", %{code: "not_found"})
    socket = :sys.get_state(view.pid).socket
    assert socket.assigns.native_subscriptions.topics == %{}
    assert socket.assigns.page_title == nil
    send(view.pid, message)
    refute has_element?(view, "#trip-shell")
  end

  test "native trip callbacks recheck resource admission before queued studio notifications", %{
    id: id
  } do
    {:ok, view, _} = open(id)
    settle_subscriptions(view)
    other = id + 1_000_000_000
    RailsUser.insert!(%{id: other, email: "trip-new-owner-#{other}@dawarich.test"})
    Repo.query!("UPDATE trips SET user_id=$1 WHERE id=$2", [other, id * 10], log: false)
    send(view.pid, {DawarichWeb.VideoStudioLiveComponent, {:saved, 1, nil}})
    refute has_element?(view, "#trip-shell")
    assert_push_event(view, "map:clear", %{code: "not_found"})
    assert :sys.get_state(view.pid).socket.assigns.current_scope == nil
  end

  test "native trip refuses an inactive initial principal without constructing studio owners", %{
    id: id
  } do
    Repo.query!("UPDATE users SET status=0 WHERE id=$1", [id], log: false)
    {:ok, view, _} = open(id)
    refute has_element?(view, "#trip-shell, [phx-hook=PosterStudio], [phx-hook=VideoStudio]")
    assert has_element?(view, "p[role=alert]", "unauthorized")
    assert :sys.get_state(view.pid).socket.assigns.page == nil
  end

  test "native trip actor refusal clears its title and editor before a queued callback", %{id: id} do
    {:ok, view, _} = open(id)
    settle_subscriptions(view)
    render_click(view, "trip:note:edit", %{"day" => "2026-06-02"})
    assert :sys.get_state(view.pid).socket.assigns.note_editor != nil
    Repo.query!("UPDATE users SET status=0 WHERE id=$1", [id], log: false)
    send(view.pid, {DawarichWeb.VideoStudioLiveComponent, {:saved, 1, nil}})
    refute has_element?(view, "#trip-shell")
    socket = :sys.get_state(view.pid).socket
    assert socket.assigns.page_title == nil
    assert socket.assigns.note_editor == nil
    assert socket.assigns.posters == []
    assert socket.assigns.native_subscriptions.topics == %{}
    assert has_element?(view, "p[role=alert]", "unauthorized")
  end

  test "native trip refusal releases its gallery listener without disturbing another owner", %{
    id: id
  } do
    {:ok, view, _} = open(id)
    settle_subscriptions(view)
    other = id + 1_000_000_000

    RailsUser.insert!(%{
      id: other,
      email: "independent-trip-#{other}@dawarich.test",
      settings: %{"timezone" => "UTC"}
    })

    TripsSeeds.trip!(%{
      id: other * 10,
      user_id: other,
      name: "Independent trip",
      started_at: ~N[2026-06-01 12:00:00],
      ended_at: ~N[2026-06-03 12:00:00]
    })

    {:ok, independent, _} = open(other)
    settle_subscriptions(independent)
    topic = Dawarich.Posters.Dependencies.Progress.stream(id) |> Bus.channel()
    other_topic = Dawarich.Posters.Dependencies.Progress.stream(other) |> Bus.channel()
    assert gallery_subscribed?(view.pid, topic)
    assert gallery_subscribed?(independent.pid, other_topic)
    Repo.query!("DELETE FROM trips WHERE id=$1", [id * 10], log: false)
    render_click(view, "trip:day", %{"day" => "2026-06-02"})
    refute gallery_subscribed?(view.pid, topic)
    assert gallery_subscribed?(independent.pid, other_topic)
    assert has_element?(independent, "#trip-shell h1", "Independent trip")
  end

  defp gallery_subscribed?(pid, topic) do
    subscriptions = :sys.get_state(Bus) |> elem(1) |> Map.get(:subscriptions, %{})

    case Map.get(subscriptions, {:channel, topic}) do
      {:subscribed, subscribers} ->
        MapSet.member?(subscribers, pid)

      {:subscribing, subscribers, excluded} ->
        MapSet.member?(subscribers, pid) and not MapSet.member?(excluded, pid)

      {:unsubscribing, subscribers} ->
        MapSet.member?(subscribers, pid)

      _ ->
        false
    end
  end

  defp settle_subscriptions(view) do
    topics = :sys.get_state(view.pid).socket.assigns.native_subscriptions.topics

    for _ <- Map.keys(topics),
        do: assert_push_event(view, "map:invalidate", %{kind: "reconnect"}, 1000)

    render(view)
  end

  defp open(id, resource \\ nil) do
    path = "/trips/#{resource || id * 10}"

    RailsUser.signed_in(id)
    |> RailsUser.connecting_as(id)
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_private(:phoenix_endpoint, @endpoint)
    |> Map.merge(%{
      request_path: path,
      path_info: ["trips", to_string(resource || id * 10)],
      query_string: ""
    })
    |> Plug.Conn.fetch_query_params()
    |> Dawarich.Test.NativeM6IntegrationRouter.call([])
    |> live()
  end
end
