defmodule DawarichWeb.NativeM6PublicDeliveryTest do
  use Dawarich.DataCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.{Cable.Bus, RailsMessages}
  alias Dawarich.Test.RailsUser
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
    uuid = Ecto.UUID.generate()
    RailsUser.insert!(%{id: id, email: "native-public-delivery-#{id}@dawarich.test"})
    stamp = NaiveDateTime.utc_now()

    Repo.insert_all("shared_links", [
      %{
        id: Ecto.UUID.dump!(uuid),
        user_id: id,
        resource_type: 3,
        name: "Public live",
        settings: %{},
        created_at: stamp,
        updated_at: stamp
      }
    ])

    %{uuid: uuid}
  end

  test "production public live delivery owns subscription and refuses a revoked queued event", %{
    uuid: uuid
  } do
    conn =
      build_conn()
      |> Plug.Conn.put_private(:live_view_connect_info, %{session: %{}})
      |> get("/s/#{uuid}")

    {:ok, view, _} = live(conn)
    topic = RailsMessages.broadcasting(["shared_location", {:shared_link, uuid}])
    state = :sys.get_state(view.pid).socket.assigns[:native_subscriptions]
    assert is_map(state) == true
    assert Map.keys(state.topics) == [topic]

    message =
      {:redix_pubsub, self(), make_ref(), :message,
       %{channel: Bus.channel(topic), payload: "synthetic-public-location"}}

    send(view.pid, message)
    assert_push_event(view, "map:invalidate", %{kind: "public"})
    assert has_element?(view, "#native-public-map")
    rows("UPDATE shared_links SET revoked_at=now() WHERE id=$1::text::uuid", [uuid])
    send(view.pid, message)
    refute has_element?(view, "#native-public-map")
    assert_push_event(view, "map:clear", %{code: "not_found"})
    assert :sys.get_state(view.pid).socket.assigns.native_subscriptions.topics == %{}
    send(view.pid, message)
    refute has_element?(view, "#native-public-map")
    refute :sys.get_state(view.pid).socket.assigns.public_config
  end
end
