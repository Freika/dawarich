defmodule DawarichWeb.NativeMapDeliveryAuthTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.{Repo, RailsMessages}
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint
  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    RailsUser.insert!(%{id: 881_402, email: "delivery@synthetic.test"})
    Application.put_env(:dawarich, :native_map_bus_owner, self())
    on_exit(fn -> Application.delete_env(:dawarich, :native_map_bus_owner) end)
    :ok
  end

  test "callback admission refusal releases subscriptions before halting a native LiveView" do
    conn =
      RailsUser.signed_in(881_402)
      |> RailsUser.connecting_as(881_402)
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_private(:phoenix_endpoint, @endpoint)
      |> Plug.Conn.fetch_query_params()
      |> Dawarich.Test.NativeMapDeliveryRouter.call([])

    {:ok, view, _} = live(conn)
    topic = RailsMessages.broadcasting(["points", {:user, 881_402}])
    assert_receive {:native_subscribe, ^topic}
    Repo.query!("UPDATE users SET deleted_at=now() WHERE id=$1", [881_402])
    send(view.pid, {:native_message, topic, "[52,13,80,10,123,9,1,\"\"]"})
    assert_redirect(view, "/users/sign_in")
    assert_receive {:native_unsubscribe, ^topic}
  end
end
