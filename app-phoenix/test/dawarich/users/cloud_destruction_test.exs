defmodule Dawarich.Users.CloudDestructionTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Auth.AccountDestroy
  alias Dawarich.Jobs.{Dispatch, Ownership, Processed}
  alias Dawarich.Users.{DestroyWorker, DestructionWebhookWorker}
  alias Dawarich.Test.RailsUser

  @env %{"MANAGER_URL" => "https://manager.example.invalid", "JWT_SECRET_KEY" => "synthetic-l1"}

  setup do
    saved = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if saved,
        do: System.put_env("DAWARICH_RAILS", saved),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    start_oban(__MODULE__)
    Ownership.put!(ScratchRepo, "command:users.destruction_webhook", :oban)

    user =
      RailsUser.insert!(
        %{
          id: System.unique_integer([:positive]),
          email: "delete-#{Ecto.UUID.generate()}@example.invalid",
          provider: "openid_connect"
        },
        ScratchRepo
      )

    context = AccountDestroy.context(%{repo: ScratchRepo, self_hosted: true})
    %{user: user, context: context}
  end

  test "L1 hard deletion commits exactly one Manager unlink with captured identity", c do
    assert {:ok, :scheduled} =
             AccountDestroy.request(c.user.id, %{"confirm_email" => c.user.email}, c.context)

    [[root]] = rows("SELECT event_id::text FROM job_outbox WHERE command_type='users.destroy'")
    assert %{dispatched: 1} = Dispatch.run(repo: ScratchRepo, oban: __MODULE__)

    [[deletion]] =
      rows("SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Users.DestroyWorker'")

    assert :ok = DestroyWorker.perform(%Oban.Job{args: deletion})
    assert rows("SELECT id FROM users WHERE id=$1", [c.user.id]) == []
    event = Dawarich.AfterCommit.identity(root, "users.destruction_webhook")

    assert rows(
             "SELECT event_id::text,payload,aggregate_id FROM job_outbox WHERE command_type='users.destruction_webhook'"
           ) ==
             [[event, %{"user_id" => c.user.id, "email" => c.user.email}, c.user.id]]

    assert rows(
             "SELECT id FROM oban.oban_jobs WHERE worker='Dawarich.Users.DestructionWebhookWorker'"
           ) == []

    assert %{dispatched: 1} = Dispatch.run(repo: ScratchRepo, oban: __MODULE__)

    [[args]] =
      rows(
        "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Users.DestructionWebhookWorker'"
      )

    parent = self()

    transport = fn :post, origin, path, headers, body, skip, timeout, opts ->
      refute ScratchRepo.in_transaction?()
      assert origin == @env["MANAGER_URL"]
      assert path == "/api/v1/users/unlink"
      assert headers == [{"Content-Type", "application/json"}, {"Accept", "application/json"}]
      assert skip == false
      assert timeout == 10_000
      assert opts[:total_timeout] == 10_000

      assert decode(body) == %{
               "user_id" => c.user.id,
               "email" => c.user.email,
               "action" => "destroy_user"
             }

      send(parent, :unlink)
      {:ok, 500, [], "Rails ignores status"}
    end

    assert :ok = DestructionWebhookWorker.run(ScratchRepo, args, env: @env, transport: transport)
    assert_receive :unlink
    assert :ok = DestructionWebhookWorker.run(ScratchRepo, args, env: @env, transport: transport)
    refute_received :unlink
    assert Processed.done?(ScratchRepo, event)
    assert :ok = DestroyWorker.run(ScratchRepo, deletion)

    assert rows("SELECT count(*) FROM job_outbox WHERE command_type='users.destruction_webhook'") ==
             [[1]]
  end

  test "L1 deletion rollback family refusal and replay cannot send an unlink", c do
    assert {:error, :password_required} = AccountDestroy.request(c.user.id, %{}, c.context)

    assert :ok =
             DestroyWorker.run(ScratchRepo, %{
               "user_id" => c.user.id,
               "event_id" => Ecto.UUID.generate()
             })

    assert rows("SELECT event_id FROM job_outbox") == []

    [[family]] =
      rows(
        "INSERT INTO families(creator_id,name,created_at,updated_at) VALUES($1,'synthetic',now(),now()) RETURNING id",
        [c.user.id]
      )

    other =
      RailsUser.insert!(
        %{
          id: System.unique_integer([:positive]),
          email: "keep-#{Ecto.UUID.generate()}@example.invalid"
        },
        ScratchRepo
      )

    for {id, role} <- [{c.user.id, 0}, {other.id, 1}] do
      rows(
        "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES($1,$2,$3,now(),now())",
        [family, id, role]
      )
    end

    assert {:error, :cannot_delete_account} =
             AccountDestroy.request(c.user.id, %{"confirm_email" => c.user.email}, c.context)

    rows("UPDATE users SET deleted_at=now() WHERE id=$1", [c.user.id])
    args = %{"user_id" => c.user.id, "event_id" => Ecto.UUID.generate()}

    assert {:cancel, "account deletion blocked by family members"} =
             DestroyWorker.run(ScratchRepo, args)

    assert rows("SELECT event_id FROM job_outbox") == []
    rows("DELETE FROM family_memberships WHERE family_id=$1", [family])
    rows("DELETE FROM families WHERE id=$1", [family])

    rows(
      "CREATE FUNCTION l1_refuse_deletion() RETURNS trigger AS $$ BEGIN RAISE EXCEPTION 'synthetic'; END; $$ LANGUAGE plpgsql"
    )

    rows(
      "CREATE TRIGGER l1_cleanup_failure BEFORE DELETE ON users FOR EACH ROW EXECUTE FUNCTION l1_refuse_deletion()"
    )

    parent = self()
    previous_http = Application.get_env(:dawarich, :user_webhook_http)
    previous_env = Map.new(@env, fn {key, _} -> {key, System.get_env(key)} end)

    Application.put_env(:dawarich, :user_webhook_http, fn _, _, _, _ ->
      send(parent, :early_unlink)
      {:ok, 200, ""}
    end)

    System.put_env(@env)

    try do
      assert {:error, {:cleanup, :raise_exception}} = DestroyWorker.run(ScratchRepo, args)
      assert rows("SELECT id FROM users WHERE id=$1", [c.user.id]) == [[c.user.id]]
      assert rows("SELECT event_id FROM job_outbox") == []
      assert rows("SELECT id FROM oban.oban_jobs") == []
      refute Processed.done?(ScratchRepo, args["event_id"])
      refute_received :early_unlink
    after
      rows("DROP TRIGGER l1_cleanup_failure ON users")
      rows("DROP FUNCTION l1_refuse_deletion()")

      if previous_http,
        do: Application.put_env(:dawarich, :user_webhook_http, previous_http),
        else: Application.delete_env(:dawarich, :user_webhook_http)

      for {key, value} <- previous_env do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end

    Ownership.put!(ScratchRepo, "command:users.destruction_webhook", :sidekiq)
    assert {:error, :callback_owner} = DestroyWorker.run(ScratchRepo, args)
    assert rows("SELECT id FROM users WHERE id=$1", [c.user.id]) == [[c.user.id]]
    Ownership.put!(ScratchRepo, "command:users.destruction_webhook", :oban)

    tasks =
      for _ <- 1..2 do
        Task.async(fn ->
          send(parent, {:ready, self()})

          receive do
            :go -> DestroyWorker.run(ScratchRepo, args)
          end
        end)
      end

    for task <- tasks do
      pid = task.pid
      assert_receive {:ready, ^pid}
    end

    for task <- tasks, do: send(task.pid, :go)
    for task <- tasks, do: assert(Task.await(task) == :ok)
    assert :ok = DestroyWorker.run(ScratchRepo, args)

    assert rows("SELECT count(*) FROM job_outbox WHERE command_type='users.destruction_webhook'") ==
             [[1]]

    rows("DELETE FROM job_outbox WHERE command_type='users.destruction_webhook'")
    assert :ok = DestroyWorker.run(ScratchRepo, args)
    assert rows("SELECT event_id FROM job_outbox") == []
  end

  test "L1 destruction transport retry preserves identity and never acknowledges failure", c do
    args = %{"user_id" => c.user.id, "email" => c.user.email, "event_id" => Ecto.UUID.generate()}
    assert DestructionWebhookWorker.new(%{}).changes.max_attempts == 5

    for attempt <- 1..5 do
      backoff = DestructionWebhookWorker.backoff(%Oban.Job{attempt: attempt})
      assert backoff >= Integer.pow(attempt, 4) + 2
      assert backoff <= trunc(Integer.pow(attempt, 4) * 1.15 + 2)
    end

    parent = self()

    result =
      DestructionWebhookWorker.run(ScratchRepo, args,
        env: @env,
        http: fn _, _, _, _ ->
          send(parent, {:delivery_transaction, ScratchRepo.in_transaction?()})
          {:error, :timeout}
        end
      )

    assert_receive {:delivery_transaction, false}
    refute Processed.done?(ScratchRepo, args["event_id"])
    assert result == {:error, :manager_transport}

    for reason <- [:timeout, :connection] do
      transport = fn _, _, _, _, _, _, _, _ ->
        refute ScratchRepo.in_transaction?()
        {:error, reason}
      end

      assert {:error, :manager_transport} =
               DestructionWebhookWorker.run(ScratchRepo, args, env: @env, transport: transport)

      refute Processed.done?(ScratchRepo, args["event_id"])
    end

    for url <- [
          "https://user:pass@manager.example.invalid",
          "https://manager.example.invalid?x=1"
        ] do
      assert {:error, :manager_transport} =
               DestructionWebhookWorker.run(ScratchRepo, args,
                 env: Map.put(@env, "MANAGER_URL", url),
                 transport: fn _, _, _, _, _, _, _, _ ->
                   send(parent, :invalid_origin)
                   {:ok, 200, [], ""}
                 end
               )
    end

    refute_received :invalid_origin

    crash = fn _, _, _, _, body, _, _, _ ->
      send(parent, {:accepted, decode(body)})

      receive do
        :crash -> exit(:kill)
      end
    end

    {pid, monitor} =
      spawn_monitor(fn ->
        DestructionWebhookWorker.run(ScratchRepo, args, env: @env, transport: crash)
      end)

    assert_receive {:accepted, payload}
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}
    refute Processed.done?(ScratchRepo, args["event_id"])

    transport = fn _, _, _, _, body, _, _, _ ->
      assert decode(body) == payload
      send(parent, :resent)
      {:ok, 302, [], "no redirect followed"}
    end

    assert :ok = DestructionWebhookWorker.run(ScratchRepo, args, env: @env, transport: transport)
    assert_receive :resent
    assert Processed.done?(ScratchRepo, args["event_id"])
    assert :ok = DestructionWebhookWorker.run(ScratchRepo, args, env: @env, transport: transport)
    refute_received :resent

    assert {:error, :transaction_required} =
             ScratchRepo.transaction(fn ->
               DestructionWebhookWorker.run(
                 ScratchRepo,
                 %{args | "event_id" => Ecto.UUID.generate()},
                 env: @env,
                 transport: transport
               )
             end)
             |> elem(1)

    assert :ok =
             DestructionWebhookWorker.run(
               ScratchRepo,
               %{args | "event_id" => Ecto.UUID.generate()},
               env: %{"MANAGER_URL" => " "},
               transport: transport
             )

    refute_received :resent
  end

  defp decode(body) do
    [header, payload, signature] = Jason.decode!(body)["token"] |> String.split(".")
    assert Jason.decode!(Base.url_decode64!(header, padding: false)) == %{"alg" => "HS256"}

    assert Base.url_decode64!(signature, padding: false) ==
             :crypto.mac(:hmac, :sha256, @env["JWT_SECRET_KEY"], header <> "." <> payload)

    Jason.decode!(Base.url_decode64!(payload, padding: false))
  end
end
