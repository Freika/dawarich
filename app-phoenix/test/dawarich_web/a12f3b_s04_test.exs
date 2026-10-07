defmodule DawarichWeb.A12f3bS04Test do
  use Dawarich.IngestCase, async: false
  alias Dawarich.Test.A12f3bShareCase, as: S
  alias Dawarich.ShareManagement.TrackMutations
  alias DawarichWeb.{TrackShareActions, ShareManagementForm}
  import Plug.Conn

  setup do
    old = Application.get_env(:dawarich, :rails_upstream)
    listener = Dawarich.Test.RawHTTP.listen()
    :gen_tcp.close(listener.listen)
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, listener.port})
    on_exit(fn -> Application.put_env(:dawarich, :rails_upstream, old) end)
    %{actor: S.seed!()}
  end

  @tag a12f3b_case: "S04a"
  test "track share destroy and revoke invalidate the actual grant", %{actor: actor} do
    before = S.rows()
    assert {:error, 404} = TrackMutations.run(actor, 99104, :revoke, %{}, "en", now: S.now())
    assert S.rows() == before

    for action <- [:revoke, :destroy] do
      response =
        S.request(actor, "track", action, %{
          "_method" => if(action == :revoke, do: "patch", else: "delete")
        })
        |> TrackShareActions.call(action)

      assert response.status == 302
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
  test "track revoke is terminal after successful write", %{actor: actor} do
    assert {:ok, result} = TrackMutations.run(actor, 99103, :revoke, %{}, "en", now: S.now())
    before = S.rows()

    broken =
      S.request(actor, "track", :revoke)
      |> register_before_send(fn response ->
        raise "synthetic response failed: #{response.status}"
      end)

    assert_raise RuntimeError, "synthetic response failed: 302", fn ->
      ShareManagementForm.respond(broken, {"track", :revoke}, %{}, {:ok, result})
    end

    assert S.rows() == before
    assert commands() == []
    refute Dawarich.SharedLinks.active(S.id(7), S.now())
  end
end
