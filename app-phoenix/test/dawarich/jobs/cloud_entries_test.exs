defmodule Dawarich.Jobs.CloudEntriesTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Jobs.{Dispatch, Registry}
  @oban Dawarich.CloudEntriesOban
  @commands [
    {"users.creation_webhook", Dawarich.Users.CreationWebhookWorker, %{"user_id" => 42}},
    {"users.destruction_webhook", Dawarich.Users.DestructionWebhookWorker,
     %{"user_id" => 42, "email" => "synthetic@example.test"}},
    {"partnero.customer_signup", Dawarich.Partnero.CustomerSignupWorker,
     %{"user_id" => 42, "partner_key" => "synthetic"}},
    {"release.family_backfill", Dawarich.ReleaseJobs.FamilyBackfill,
     %{"phase" => "families", "after_id" => 501, "time_zone" => "Europe/Berlin"}}
  ]

  setup do
    start_oban(@oban)
    :ok
  end

  test "L1 registry resolves creation destruction referral and family commands exactly once" do
    for {type, worker, payload} <- @commands do
      outbox!(command_type: type, payload: payload)

      assert Dispatch.run(repo: ScratchRepo, oban: @oban, now: db_now(ScratchRepo)) == %{
               dispatched: 1
             }

      assert Registry.command(type) == {:ok, worker}

      assert [%{worker: ^worker, claimable: false}] =
               Enum.filter(Registry.entries(), &(&1.key == "command:" <> type))
    end

    for {type, _worker, payload} <- @commands do
      outbox!(command_type: type, command_version: 2, payload: payload)
      outbox!(command_type: type, payload: Map.put(payload, "extra", true))
    end

    outbox!(command_type: "unknown.cloud.command")

    assert Dispatch.run(repo: ScratchRepo, oban: @oban, now: db_now(ScratchRepo)) == %{
             quarantined: 9
           }

    assert rows("SELECT count(*) FROM public.job_outbox WHERE error_code='unsupported_version'") ==
             [[4]]

    assert rows("SELECT count(*) FROM public.job_outbox WHERE error_code='invalid_payload'") == [
             [4]
           ]

    assert rows("SELECT count(*) FROM public.job_outbox WHERE error_code='unknown_command'") == [
             [1]
           ]

    assert Registry.claimable() == []

    assert Dawarich.Release.Lifecycle.mode(%{"SELF_HOSTED" => "false", "DAWARICH_RAILS" => "off"}) ==
             {:error, :cloud_native_lifecycle}
  end

  test "L1 dispatch preserves Cloud callback and family operation envelopes" do
    for {type, worker, payload} <- @commands do
      id = outbox!(command_type: type, payload: payload, aggregate_id: 42)

      assert Dispatch.run(repo: ScratchRepo, oban: @oban, now: db_now(ScratchRepo)) == %{
               dispatched: 1
             }

      name = inspect(worker)

      assert [[^name, args, %{"command_version" => 1}]] =
               rows("SELECT worker,args,meta FROM oban.oban_jobs WHERE args->>'event_id'=$1", [id])

      assert args["event_id"] == id

      assert rows("SELECT aggregate_id,state FROM public.job_outbox WHERE event_id=$1", [
               Ecto.UUID.dump!(id)
             ]) == [[42, "dispatched"]]

      if type == "release.family_backfill" do
        assert args["version"] == 1
        assert args["cursor"] == payload
      else
        assert args == Map.put(payload, "event_id", id)
      end
    end

    assert rows("SELECT count(*) FROM public.job_outbox WHERE state='quarantined'") == [[0]]
  end
end
