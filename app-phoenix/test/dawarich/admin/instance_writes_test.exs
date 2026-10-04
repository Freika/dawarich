defmodule Dawarich.Admin.InstanceWritesTest do
  use ExUnit.Case, async: false
  alias Dawarich.Admin.{InstancePage, InstanceWrites}
  alias Dawarich.{Accounts, ActiveRecordEncryption, Redis, Repo}
  alias Dawarich.Test.RailsUser
  @now ~U[2026-10-04 10:00:00.000000Z]

  defmodule LaterFailureRepo do
    defdelegate transaction(fun), to: Dawarich.Repo

    def query!(sql, params, opts) do
      if String.starts_with?(sql, "INSERT INTO instance_settings") and
           hd(params) == "reverse_geocoding_rps",
         do: raise("synthetic later persistence failure"),
         else: Dawarich.Repo.query!(sql, params, opts)
    end
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Repo.query!("DELETE FROM instance_settings", [], log: false)

    RailsUser.insert!(%{
      id: 15501,
      email: "a10b-instance-admin@example.invalid",
      admin: true,
      settings: %{"locale" => "en", "timezone" => "UTC"}
    })

    %{
      actor: Accounts.get(15501),
      context: %{self_hosted: true, oidc: false, locale: "en", env: %{}, clock: fn -> @now end}
    }
  end

  test "saves unpinned fields and Rails-decryptable secrets without exposure", c do
    assert Code.ensure_loaded?(InstanceWrites), "instance writes must exist"

    if is_nil(Process.whereis(Redis)),
      do: start_supervised!({Redix, {System.fetch_env!("PHOENIX_TEST_REDIS_URL"), [name: Redis]}})

    subscriber =
      start_supervised!(%{
        id: Redix.PubSub,
        start: {Redix.PubSub, :start_link, [System.fetch_env!("PHOENIX_TEST_REDIS_URL"), []]}
      })

    {:ok, ref} = Redix.PubSub.subscribe(subscriber, "dawarich:instance_settings", self())

    assert_receive {:redix_pubsub, ^subscriber, ^ref, :subscribed,
                    %{channel: "dawarich:instance_settings"}}

    input = [
      {"photon_api_host", "HTTPS://PHOTON.EXAMPLE.INVALID/"},
      {"geoapify_api_key", "synthetic-instance-key"},
      {"store_geodata", "false"},
      {"reverse_geocoding_rps", "2.5"}
    ]

    context = %{c.context | env: %{"PHOTON_API_HOST" => "pinned.example.invalid"}}
    assert {:ok, ["PHOTON_API_HOST"]} = InstanceWrites.call(c.actor, params(input), context)

    assert Repo.query!("SELECT value FROM instance_settings WHERE key='photon_api_host'", [],
             log: false
           ).rows == []

    assert [[nil, encrypted, created, updated]] =
             Repo.query!(
               "SELECT value,encrypted_value,created_at,updated_at FROM instance_settings WHERE key='geoapify_api_key'",
               [],
               log: false
             ).rows

    {:ok, key} = ActiveRecordEncryption.key(%{})
    assert {:ok, "synthetic-instance-key"} = ActiveRecordEncryption.decrypt(encrypted, key)
    assert created == DateTime.to_naive(@now) and updated == created

    assert Repo.query!("SELECT value FROM instance_settings WHERE key='store_geodata'", [],
             log: false
           ).rows == [[false]]

    for name <- ~w(geoapify_api_key store_geodata reverse_geocoding_rps) do
      assert_receive {:redix_pubsub, ^subscriber, ^ref, :message,
                      %{channel: "dawarich:instance_settings", payload: payload}}

      assert Jason.decode!(payload) == %{"key" => name}
    end

    refute_receive {:redix_pubsub, ^subscriber, ^ref, :message, _}
    {:ok, page} = InstancePage.load(Repo, context.env)
    refute inspect(page) =~ "synthetic-instance-key"
    assert page.fields["geoapify_api_key"].value == nil

    Repo.query!(
      "UPDATE instance_settings SET encrypted_value='corrupt-synthetic' WHERE key='geoapify_api_key'",
      [],
      log: false
    )

    quiet = Map.put(context, :command, fn _ -> {:ok, 0} end)

    assert {:ok, []} =
             InstanceWrites.call(
               c.actor,
               params([{"geoapify_api_key", "synthetic-replacement"}]),
               quiet
             )

    [[nil, encrypted, ^created]] =
      Repo.query!(
        "SELECT value,encrypted_value,created_at FROM instance_settings WHERE key='geoapify_api_key'",
        [],
        log: false
      ).rows

    assert {:ok, "synthetic-replacement"} = ActiveRecordEncryption.decrypt(encrypted, key)

    Repo.query!(
      "UPDATE instance_settings SET encrypted_value='corrupt-synthetic' WHERE key='geoapify_api_key'",
      [],
      log: false
    )

    clear =
      Map.put(params([{"geoapify_api_key", ""}]), "instance_settings_clear", %{
        "geoapify_api_key" => "1"
      })

    assert {:ok, []} = InstanceWrites.call(c.actor, clear, quiet)

    assert Repo.query!(
             "SELECT value,encrypted_value FROM instance_settings WHERE key='geoapify_api_key'",
             [],
             log: false
           ).rows == [[nil, nil]]

    Repo.query!("UPDATE users SET admin=false WHERE id=15501", [], log: false)
    before = snapshot()
    assert {:handoff, :actor} = InstanceWrites.call(c.actor, params(input), quiet)
    assert snapshot() == before
  end

  test "preserves earlier saves on later failure and tolerates publish failure", c do
    assert Code.ensure_loaded?(InstanceWrites), "instance writes must exist"
    context = Map.put(c.context, :command, fn _ -> {:error, :synthetic_publish_failure} end)

    assert {:invalid, _} =
             InstanceWrites.call(
               c.actor,
               params([{"store_geodata", "false"}, {"photon_api_host", "bad host"}]),
               context
             )

    assert snapshot() == []
    failing = Map.put(context, :repo, LaterFailureRepo)

    assert {:terminal, :persistence} =
             InstanceWrites.call(
               c.actor,
               params([
                 {"store_geodata", "false"},
                 {"reverse_geocoding_rps", "2.5"},
                 {"nominatim_api_host", "never.example.invalid"}
               ]),
               failing
             )

    assert Repo.query!("SELECT key,value FROM instance_settings ORDER BY key", [], log: false).rows ==
             [["store_geodata", false]]

    assert {:ok, []} = InstanceWrites.call(c.actor, params([{"store_geodata", "true"}]), context)

    assert Repo.query!("SELECT value FROM instance_settings WHERE key='store_geodata'", [],
             log: false
           ).rows == [[true]]

    {:ok, page} = InstancePage.load(Repo, %{})

    assert Enum.all?(page.fields, fn {_, field} ->
             field.kind != :secret or is_nil(field.value)
           end)
  end

  defp params(input), do: %{"instance_settings" => input}

  defp snapshot,
    do:
      Repo.query!("SELECT key,value,encrypted_value FROM instance_settings ORDER BY key", [],
        log: false
      ).rows
end
