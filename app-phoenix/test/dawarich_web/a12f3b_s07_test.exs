defmodule DawarichWeb.A12f3bS07Test do
  use Dawarich.IngestCase, async: false
  alias Dawarich.Test.A12f3bShareCase, as: S
  alias Dawarich.ShareManagement.Mutations
  alias Dawarich.Sharing
  alias Dawarich.Cable.Bus

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
  test "native S07a live trip and hub commands preserve all five writes", %{actor: actor} do
    scope = Dawarich.Accounts.Scope.for_user(actor, "en")

    for type <- [:live, :trip] do
      resource =
        if type == :trip,
          do: %{type: type, owner_id: actor.id, id: 99101},
          else: %{type: type, owner_id: actor.id}

      for action <- [:create, :regenerate, :regenerate_phrase, :revoke, :create, :destroy] do
        params = if action == :create, do: S.params("track"), else: %{}
        assert {:ok, result} = Sharing.change(scope, resource, action, params, now: S.now())
        refute inspect(result) =~ "magic_phrase"
      end
    end

    assert {:ok, _} =
             Sharing.change(scope, %{type: :live, owner_id: actor.id}, :create, S.params("track"),
               now: S.now()
             )

    before = S.rows()

    assert {:error, :stale_session} =
             Sharing.change(
               Dawarich.Accounts.Scope.for_user(nil, "en"),
               %{type: :live, owner_id: actor.id},
               :create,
               S.params("track"),
               now: S.now()
             )

    assert S.rows() == before
  end

  @tag a12f3b_case: "S07b"
  @tag a12f3b_r15: "R15k05"
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
