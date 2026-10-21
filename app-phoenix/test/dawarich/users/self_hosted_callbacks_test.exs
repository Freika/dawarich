defmodule Dawarich.Users.SelfHostedCallbacksTest do
  use Dawarich.JobsCase, async: false
  import Dawarich.AnomalyCase
  alias Dawarich.Auth.{AccountDestroy, Registration}
  alias Dawarich.Jobs.{Dispatch, Ownership, Processed}
  alias Dawarich.Users.{CreationEffects, DestroyWorker}

  @keys ~w(SELF_HOSTED MANAGER_URL JWT_SECRET_KEY PARTNERO_API_KEY DAWARICH_RAILS)
  @callbacks ~w(users.creation_webhook users.destruction_webhook partnero.customer_signup families.auto_create families.member_sync)

  setup do
    previous = Map.new(@keys, &{&1, System.get_env(&1)})

    on_exit(fn ->
      for {key, value} <- previous do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end)

    start_oban(__MODULE__)
    for type <- @callbacks, do: Ownership.put!(ScratchRepo, "command:" <> type, :oban)
    :ok
  end

  test "self-hosted creation and default deletion publish no Cloud callbacks even with Manager configured" do
    for env <- [
          %{},
          %{"SELF_HOSTED" => "true"},
          %{
            "SELF_HOSTED" => "true",
            "MANAGER_URL" => "https://manager.example.invalid",
            "JWT_SECRET_KEY" => "synthetic-self-hosted",
            "PARTNERO_API_KEY" => "synthetic-self-hosted"
          }
        ] do
      for key <- @keys, do: System.delete_env(key)
      System.put_env(Map.put(env, "DAWARICH_RAILS", "off"))

      context = %{
        repo: ScratchRepo,
        env: env,
        registration_enabled: true,
        log_rounds: 4,
        oidc: false
      }

      assert {:ok, result} =
               Registration.register(
                 %{
                   "email" => "self-hosted-#{Ecto.UUID.generate()}@example.invalid",
                   "password" => "synthetic-password",
                   "password_confirmation" => "synthetic-password"
                 },
                 %{"partnero_referral" => "synthetic-referral"},
                 context
               )

      assert result.signed_in
      assert result.session["partnero_referral"] == "synthetic-referral"

      for skip <- [false, true] do
        id = user!()

        assert {:ok, :ok} =
                 ScratchRepo.transaction(fn ->
                   CreationEffects.apply(ScratchRepo, id, env: env, skip_auto_trial: skip)
                 end)
      end

      assert callbacks() == []
      user = result.user
      rows("UPDATE users SET provider='openid_connect' WHERE id=$1", [user.id])
      deletion = AccountDestroy.context(%{repo: ScratchRepo, self_hosted: true})

      assert {:ok, :scheduled} =
               AccountDestroy.request(user.id, %{"confirm_email" => user.email}, deletion)

      assert %{dispatched: 1} =
               Dispatch.run(repo: ScratchRepo, oban: __MODULE__, now: db_now(ScratchRepo))

      [[args]] =
        rows("SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Users.DestroyWorker'")

      assert :ok = DestroyWorker.perform(%Oban.Job{args: args})
      assert rows("SELECT id FROM users WHERE id=$1", [user.id]) == []
      assert Processed.done?(ScratchRepo, args["event_id"])
      assert callbacks() == []
      assert :ok = DestroyWorker.perform(%Oban.Job{args: args})
      assert callbacks() == []
      Dawarich.JobsCase.reset!(ScratchRepo)
    end
  end

  defp callbacks,
    do:
      rows("SELECT command_type FROM job_outbox WHERE command_type=ANY($1::text[])", [@callbacks])
end
