defmodule DawarichWeb.PlacesLiveAuthTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest
  import Phoenix.ConnTest
  alias Dawarich.Test.NativePlaces, as: N
  @endpoint DawarichWeb.Endpoint
  setup do: N.setup!()

  test "native Places refuse revoked identity on event params info and async", ctx do
    for channel <- [:event, :params, :info] do
      {:ok, view, _} = live(N.conn(ctx.actor), "/places")
      N.revoke(ctx.actor)

      case channel do
        :event -> render_click(view, "request_delete", %{"id" => "118501"})
        :params -> render_patch(view, "/places?page=2")
        :info -> send(view.pid, :places_probe)
      end

      assert_redirect(view, "/users/sign_in")

      Dawarich.Repo.query!(
        "UPDATE users SET encrypted_password=$1 WHERE id=$2",
        [ctx.actor.encrypted_password, ctx.actor.id], log: false)
    end

    {:ok, view, _} = live(N.conn(ctx.actor), "/places")
    socket = :sys.get_state(view.pid).socket
    N.revoke(ctx.actor)
    socket = Phoenix.Component.assign(socket, :current_user, Dawarich.Accounts.get(ctx.actor.id))

    for delivery <- [
          fn -> Phoenix.LiveView.Lifecycle.handle_event("unknown", %{}, socket) end,
          fn -> Phoenix.LiveView.Lifecycle.handle_params(%{}, "/places", socket) end,
          fn -> Phoenix.LiveView.Lifecycle.handle_info(:places_probe, socket) end,
          fn -> Phoenix.LiveView.Lifecycle.handle_async(:nearby, {:ok, []}, socket) end
        ] do
      assert {:halt, refused} = delivery.()
      assert refused.redirected == {:redirect, %{to: "/users/sign_in", status: 302}}
      assert refused.assigns.entries == []
    end

    assert Dawarich.Repo.query!("SELECT id FROM places WHERE user_id=$1", [ctx.actor.id]).rows ==
             []
  end
end
