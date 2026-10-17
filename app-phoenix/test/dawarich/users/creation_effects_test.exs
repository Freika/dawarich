defmodule Dawarich.Users.CreationEffectsTest do
  use Dawarich.JobsCase
  import Dawarich.AnomalyCase
  alias Dawarich.Users.{CreationEffects, CreationWebhookWorker}
  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.AfterCommit

  @env %{
    "SELF_HOSTED" => "false",
    "TIME_ZONE" => "Europe/Berlin",
    "MANAGER_URL" => "https://manager.example.invalid",
    "JWT_SECRET_KEY" => "synthetic-oracle-key"
  }
  @commands ~w(mail.user.welcome users.explore_features_mail users.creation_webhook)

  setup do
    for type <- @commands, do: Ownership.put!(ScratchRepo, "command:" <> type, :oban)
    :ok
  end

  test "L1 ordinary Cloud creation matches Rails trial dates API key and delayed mail" do
    for source <- oracle()["trials"] do
      id = user!()
      {:ok, now, _} = DateTime.from_iso8601(source["now"])

      assert {:ok, :ok} =
               ScratchRepo.transaction(fn ->
                 CreationEffects.apply(ScratchRepo, id, env: @env, now: now, locale: "de")
               end)

      [[status, plan, expiry, key]] =
        rows("SELECT status,plan,active_until,api_key FROM users WHERE id=$1", [id])

      assert status == 2
      assert plan == %{"lite" => 0, "pro" => 1, "family" => 2}[source["plan"]]

      assert DateTime.from_naive!(expiry, "Etc/UTC")
             |> DateTime.truncate(:second)
             |> DateTime.to_iso8601() ==
               source["active_until"]

      assert is_binary(key) and Regex.match?(~r/\A[0-9a-f]{64}\z/, key) == source["key_valid"]

      assert [
               ["mail.user.welcome", %{"user_id" => id, "locale" => "de"}, welcome_at],
               ["users.creation_webhook", _, manager_at],
               ["users.explore_features_mail", %{"user_id" => id, "locale" => "de"}, at]
             ] =
               rows(
                 "SELECT command_type,payload,scheduled_at FROM job_outbox WHERE aggregate_id=$1 ORDER BY command_type",
                 [id]
               )

      assert iso(at) == source["explore_at"]
      assert DateTime.compare(welcome_at, now) == :eq
      assert DateTime.compare(manager_at, now) == :eq
    end
  end

  test "L1 skip auto trial preserves supplied state and sends only Manager creation" do
    id = user!()
    rows("UPDATE users SET status=3,active_until='2030-01-01' WHERE id=$1", [id])
    opts = [env: @env, now: ~U[2026-03-27 12:00:00Z], skip_auto_trial: true]

    for _ <- 1..2,
        do:
          assert(
            {:ok, :ok} =
              ScratchRepo.transaction(fn -> CreationEffects.apply(ScratchRepo, id, opts) end)
          )

    [[status, expiry, key]] =
      rows("SELECT status,active_until,api_key FROM users WHERE id=$1", [id])

    assert status == 3

    assert iso(DateTime.from_naive!(expiry, "Etc/UTC")) ==
             oracle()["skip"]["active_until"]

    assert is_binary(key) and Regex.match?(~r/\A[0-9a-f]{64}\z/, key)
    assert [["users.creation_webhook"]] = rows("SELECT command_type FROM job_outbox")
    [[event]] = rows("SELECT event_id FROM job_outbox")
    Processed.mark!(ScratchRepo, Ecto.UUID.load!(event), "users.creation_webhook")
    rows("DELETE FROM job_outbox")
    rows("UPDATE users SET status=1,plan=2 WHERE id=$1", [id])

    assert {:ok, :ok} =
             ScratchRepo.transaction(fn -> CreationEffects.apply(ScratchRepo, id, opts) end)

    assert rows("SELECT status,plan,api_key=$2 FROM users WHERE id=$1", [id, key]) == [
             [1, 2, true]
           ]

    assert rows("SELECT count(*) FROM job_outbox") == [[0]]
  end

  test "L1 creation intents commit together and survive concurrent completion replay" do
    id = user!()
    assert {:error, :transaction_required} = CreationEffects.apply(ScratchRepo, id, env: @env)
    Ownership.put!(ScratchRepo, "command:users.creation_webhook", :sidekiq)

    assert {:error, :webhook_owner} =
             ScratchRepo.transaction(fn -> CreationEffects.apply(ScratchRepo, id, env: @env) end)

    assert rows("SELECT status,api_key FROM users WHERE id=$1", [id]) == [[0, ""]]
    assert rows("SELECT count(*) FROM job_outbox") == [[0]]
    Ownership.put!(ScratchRepo, "command:users.creation_webhook", :oban)
    parent = self()

    tasks =
      for _ <- 1..2 do
        Task.async(fn ->
          send(parent, {:ready, self()})

          receive do
            :go -> :ok
          end

          ScratchRepo.transaction(fn -> CreationEffects.apply(ScratchRepo, id, env: @env) end)
        end)
      end

    pids =
      for _ <- tasks do
        assert_receive {:ready, pid}
        pid
      end

    Enum.each(pids, &send(&1, :go))
    for task <- tasks, do: assert(Task.await(task) == {:ok, :ok})
    assert rows("SELECT count(*) FROM job_outbox") == [[3]]
    assert Processed.done?(ScratchRepo, AfterCommit.identity(id, "users.creation_effects"))
  end

  test "L1 Manager creation worker matches Rails signed payload and safe HTTP policy" do
    id = user!()

    rows(
      "UPDATE users SET first_name='Ada',last_name='Lovelace',status=2,active_until='2026-10-06 12:00:00' WHERE id=$1",
      [id]
    )

    event = Ecto.UUID.generate()
    args = %{"user_id" => id, "event_id" => event}
    parent = self()

    transport = fn method, origin, path, headers, body, verify, timeout, _ ->
      refute ScratchRepo.in_transaction?()

      send(
        parent,
        {:request, method, origin, path, headers, Jason.decode!(body), verify, timeout}
      )

      {:ok, 500, [], "ignored"}
    end

    assert :ok = CreationWebhookWorker.run(ScratchRepo, args, env: @env, transport: transport)

    assert_receive {:request, :post, "https://manager.example.invalid", "/api/v1/users", _,
                    %{"token" => token}, false, 10_000}

    [header, claims, sig] = String.split(token, ".")

    valid =
      Base.url_decode64!(sig, padding: false) ==
        :crypto.mac(:hmac, :sha256, @env["JWT_SECRET_KEY"], header <> "." <> claims)

    assert valid

    assert Map.drop(Jason.decode!(Base.url_decode64!(claims, padding: false)), [
             "user_id",
             "email"
           ]) == oracle()["manager"]

    assert :ok = CreationWebhookWorker.run(ScratchRepo, args, env: @env, transport: transport)
    refute_received {:request, _, _, _, _, _, _, _}
    failed = %{args | "event_id" => Ecto.UUID.generate()}

    assert {:error, :manager_transport} =
             CreationWebhookWorker.run(ScratchRepo, failed,
               env: @env,
               transport: fn _, _, _, _, _, _, _, _ -> {:error, :timeout} end
             )

    refute Processed.done?(ScratchRepo, failed["event_id"])

    for missing <- [-1, id] do
      if missing == id, do: rows("UPDATE users SET deleted_at=now() WHERE id=$1", [id])

      assert :ok =
               CreationWebhookWorker.run(
                 ScratchRepo,
                 %{"user_id" => missing, "event_id" => Ecto.UUID.generate()},
                 env: @env,
                 transport: transport
               )
    end

    refute_received {:request, _, _, _, _, _, _, _}
  end

  defp iso(at), do: at |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp oracle,
    do:
      File.read!(Path.expand("../../fixtures/cloud_creation/source.json", __DIR__))
      |> Jason.decode!()
end
