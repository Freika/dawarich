defmodule DawarichWeb.A12f3bS07Test do
  use Dawarich.IngestCase, async: false
  alias Dawarich.Test.A12f3bShareCase, as: S
  alias Dawarich.ShareManagement.Mutations
  alias DawarichWeb.ShareManagementForm
  alias Dawarich.Cable.Bus
  import Plug.Conn

  setup do
    actor = S.seed!()
    old = Application.get_env(:dawarich, :rails_upstream)
    listener = Dawarich.Test.RawHTTP.listen()
    :gen_tcp.close(listener.listen)
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, listener.port})
    on_exit(fn -> Application.put_env(:dawarich, :rails_upstream, old) end)

    for spec <-
          Bus.child_specs(
            bus: true,
            url: System.fetch_env!("PHOENIX_TEST_REDIS_URL"),
            database: 1
          ),
        do: start_supervised!(spec)

    %{actor: actor}
  end

  @tag a12f3b_case: "S07a"
  test "live trip and hub residual transports preserve all five writes", %{actor: actor} do
    for type <- ["live", "trip"],
        action <- [:create, :regenerate, :regenerate_phrase, :revoke, :create, :destroy] do
      params = if action == :create, do: S.params("track"), else: %{}
      params = Map.put(params, "hub", "false")

      request =
        S.request(actor, type, action, params)
        |> Map.put(:path_params, if(type == "trip", do: %{"trip_id" => "99101"}, else: %{}))

      response = ShareManagementForm.call(request, {type, action})
      assert response.status == 200

      assert get_resp_header(response, "content-type") == [
               "text/vnd.turbo-stream.html; charset=utf-8"
             ]

      assert response.resp_body =~ ~s(action="update" target="share-hub-body")
    end

    json =
      S.request(actor, "live", :create, Map.put(S.params("track"), "format", "json"))
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")

    assert ShareManagementForm.admission(json) == :ok
    assert ShareManagementForm.call(json, {"live", :create}).status == 302
    before = S.rows()
    csrf = json |> delete_req_header("x-csrf-token")
    assert {:replay, "authenticity token"} = ShareManagementForm.admission(csrf)
    assert S.rows() == before
  end

  @tag a12f3b_case: "S07b"
  test "live share revocation publishes one native ended event", %{actor: actor} do
    stream = Dawarich.RailsMessages.broadcasting(["shared_location", {:shared_link, S.id(1)}])
    {:ok, ref} = Bus.subscribe(stream)
    assert_receive {:redix_pubsub, _, ^ref, :subscribed, _}

    assert {:ok, %{committed?: true}} =
             Mutations.run(actor, "live", nil, :revoke, %{}, "en", now: S.now())

    assert_receive {:redix_pubsub, _, ^ref, :message, %{payload: payload}}
    assert Jason.decode!(payload) == %{"revoked" => true}
    refute_receive {:redix_pubsub, _, ^ref, :message, _}
    assert commands() == []

    for {type, id, share} <- [{"trip", 99101, S.id(6)}, {"track", 99103, S.id(7)}] do
      other_stream =
        Dawarich.RailsMessages.broadcasting(["shared_location", {:shared_link, share}])

      {:ok, other_ref} = Bus.subscribe(other_stream)
      assert_receive {:redix_pubsub, _, ^other_ref, :subscribed, _}
      assert {:ok, _} = Mutations.run(actor, type, id, :revoke, %{}, "en", now: S.now())
      refute_receive {:redix_pubsub, _, ^other_ref, :message, _}
      refute_receive {:redix_pubsub, _, ^ref, :message, _}
      assert commands() == []
      Bus.unsubscribe(other_stream)
    end

    Bus.unsubscribe(stream)
  end
end
