defmodule DawarichWeb.NativeFamilyDeliveryTest do
  use Dawarich.DataCase, async: false
  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest
  alias Dawarich.Cable.Bus
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

    for user <- [id, id + 1] do
      RailsUser.insert!(%{
        id: user,
        email: "family-delivery-#{user}@dawarich.test",
        settings: %{"timezone" => "UTC"}
      })
    end

    at = NaiveDateTime.utc_now()

    Repo.insert_all("families", [
      %{id: id, creator_id: id, name: "Native delivery family", created_at: at, updated_at: at}
    ])

    Repo.insert_all(
      "family_memberships",
      for(
        {user, role} <- [{id, 0}, {id + 1, 1}],
        do: %{id: user, family_id: id, user_id: user, role: role, created_at: at, updated_at: at}
      )
    )

    %{id: id}
  end

  test "native family delivery invalidates its owner and releases a revoked listener without affecting another owner",
       %{id: id} do
    {:ok, first, _} = open(id)
    {:ok, second, _} = open(id + 1)
    topic = "family:user:#{id}"
    other_topic = "family:user:#{id + 1}"
    assert Map.has_key?(topics(first), topic)
    assert Map.has_key?(topics(second), other_topic)
    settle(first)
    settle(second)

    message = {:domain_changed, id, :location}

    Repo.query!("UPDATE families SET name=$1 WHERE id=$2", ["Family delivered", id], log: false)
    send(first.pid, message)
    assert_push_event(first, "map:invalidate", %{kind: "family"})
    assert has_element?(first, "#family-shell h1", "Family delivered")
    Repo.query!("DELETE FROM family_memberships WHERE user_id=$1", [id], log: false)
    send(first.pid, message)
    assert_push_event(first, "map:clear", %{code: "not_found"})
    assert topics(first) == %{}
    refute has_element?(first, "#family-shell")
    send(second.pid, {:domain_changed, id + 1, :location})
    assert_push_event(second, "map:invalidate", %{kind: "family"})
    assert has_element?(second, "#family-shell")
    assert Map.has_key?(topics(second), other_topic)
  end

  test "native family queued callbacks refuse lost membership before receiving another stream", %{
    id: id
  } do
    {:ok, view, _} = open(id)
    assert map_size(topics(view)) == 1
    settle(view)
    Repo.query!("DELETE FROM family_memberships WHERE user_id=$1", [id], log: false)
    send(view.pid, :queued_family_refresh)
    refute has_element?(view, "#family-shell")
    assert_push_event(view, "map:clear", %{code: "not_found"})
    assert topics(view) == %{}
    state = :sys.get_state(view.pid).socket.assigns
    assert state.page == nil
    assert state.page_title == nil
    assert state.navbar == nil
    render_change(view, "family:sharing", %{"sharing" => %{"enabled" => "true"}})
    refute Dawarich.Accounts.get(id).settings["family"]
  end

  defp topics(view),
    do: (:sys.get_state(view.pid).socket.assigns[:native_subscriptions] || %{topics: %{}}).topics

  defp settle(view), do: render(view)

  defp open(id) do
    RailsUser.signed_in(id)
    |> RailsUser.connecting_as(id)
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_private(:phoenix_endpoint, @endpoint)
    |> Map.merge(%{request_path: "/family", path_info: ["family"], query_string: ""})
    |> Plug.Conn.fetch_query_params()
    |> Dawarich.Test.NativeM6IntegrationRouter.call([])
    |> live()
  end
end
