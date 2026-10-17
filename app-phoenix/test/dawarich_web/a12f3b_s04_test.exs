defmodule DawarichWeb.A12f3bS04Test do
  use Dawarich.IngestCase, async: false
  alias Dawarich.Test.A12f3bShareCase, as: S
  alias Dawarich.ShareManagement.TrackMutations
  alias Dawarich.Sharing
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  @endpoint DawarichWeb.Endpoint

  setup do
    old = Application.get_env(:dawarich, :rails_upstream)
    listener = Dawarich.Test.RawHTTP.listen()
    :gen_tcp.close(listener.listen)
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, listener.port})
    on_exit(fn -> Application.put_env(:dawarich, :rails_upstream, old) end)
    %{actor: S.seed!()}
  end

  @tag a12f3b_case: "S04a"
  test "native S04a track share destroy and revoke invalidate the actual grant", %{actor: actor} do
    before = S.rows()
    assert {:error, 404} = TrackMutations.run(actor, 99104, :revoke, %{}, "en", now: S.now())
    assert S.rows() == before

    for action <- [:revoke, :destroy] do
      assert {:ok, _} =
               Sharing.change(
                 Dawarich.Accounts.Scope.for_user(actor, "en"),
                 %{type: :track, owner_id: actor.id, id: 99103},
                 action,
                 %{},
                 now: S.now()
               )

      refute Dawarich.SharedLinks.active(S.id(7), S.now())

      assert {:missing, "/map/v2"} =
               TrackMutations.run(actor, 99103, action, %{}, "en", now: S.now())

      assert {:ok, %{share: share}} =
               TrackMutations.run(actor, 99103, :create, S.params("track"), "en", now: S.now())

      assert share.resource_id == 99103
    end

    assert commands() == []
  end

  @tag a12f3b_case: "S04b"
  test "native S04b failed response cannot replay a committed track revoke", %{actor: actor} do
    conn =
      Dawarich.Test.RailsUser.signed_in(actor.id)
      |> Dawarich.Test.RailsUser.connecting_as(actor.id)

    {:ok, view, _} = live(conn, "/tracks/99103/share_link/new")
    socket = :sys.get_state(view.pid).socket

    socket = %{
      socket
      | assigns:
          Map.delete(socket.assigns, :flash)
          |> Map.put(:confirmation, %{resource: socket.assigns.resource, action: :revoke})
    }

    assert_raise KeyError, fn ->
      DawarichWeb.SharingLive.Index.handle_event("sharing_confirm", %{}, socket)
    end

    before = S.rows()

    assert {:error, :not_found} =
             Sharing.change(
               Dawarich.Accounts.Scope.for_user(actor, "en"),
               %{type: :track, owner_id: actor.id, id: 99103},
               :revoke,
               %{},
               now: S.now()
             )

    assert S.rows() == before
    assert commands() == []
    refute Dawarich.SharedLinks.active(S.id(7), S.now())
  end
end
