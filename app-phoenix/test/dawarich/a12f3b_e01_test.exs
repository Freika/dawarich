defmodule Dawarich.A12f3bE01Test do
  use Dawarich.DataCase
  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.Users.{CreationWebhookWorker, DestructionWebhookWorker, WebhookCommands}

  @env %{
    "MANAGER_URL" => "https://manager.example.invalid",
    "JWT_SECRET_KEY" => "synthetic-e01-key"
  }

  setup do
    saved = Map.new(@env, fn {key, _} -> {key, System.get_env(key)} end)
    System.put_env(@env)

    on_exit(fn ->
      for {key, value} <- saved do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end)

    :ok
  end

  @tag a12f3b_case: "E01a"
  test "user webhook callbacks match source payload and Cloud policy" do
    id =
      user!(%{
        first_name: "Ada",
        last_name: "Lovelace",
        status: 2,
        active_until: ~N[2026-10-06 12:00:00.123456]
      })

    creation = %{"user_id" => id, "event_id" => Ecto.UUID.generate()}

    destroy = %{
      "user_id" => id,
      "email" => "snapshot@example.invalid",
      "event_id" => Ecto.UUID.generate()
    }

    parent = self()

    http = fn url, headers, body, timeout ->
      send(parent, {:post, url, headers, Jason.decode!(body), timeout})
      {:ok, 500, "ignored by Rails"}
    end

    opts = [env: @env, http: http]

    for worker <- [CreationWebhookWorker, DestructionWebhookWorker] do
      assert worker.args_from_command(2, %{}) == {:error, "unsupported_version"}
      assert worker.args_from_command(1, %{"user_id" => "bad"}) == {:error, "invalid_payload"}
    end

    assert CreationWebhookWorker.args_from_command(1, %{"user_id" => id}) ==
             {:ok, %{"user_id" => id}}

    assert DestructionWebhookWorker.args_from_command(1, Map.delete(destroy, "event_id")) ==
             {:ok, Map.delete(destroy, "event_id")}

    for blank <- [nil, "", "  \t"] do
      assert :ok =
               CreationWebhookWorker.run(Repo, %{creation | "event_id" => Ecto.UUID.generate()},
                 env: %{"MANAGER_URL" => blank},
                 http: http
               )

      assert :ok =
               DestructionWebhookWorker.run(Repo, %{destroy | "event_id" => Ecto.UUID.generate()},
                 env: %{"MANAGER_URL" => blank},
                 http: http
               )
    end

    refute_received {:post, _, _, _, _}

    assert :ok = CreationWebhookWorker.run(Repo, creation, opts)

    assert_receive {:post, "https://manager.example.invalid/api/v1/users", headers,
                    %{"token" => token}, nil}

    assert headers == [{"Content-Type", "application/json"}, {"Accept", "application/json"}]

    assert decode(token) == %{
             "user_id" => id,
             "email" => email(id),
             "first_name" => "Ada",
             "last_name" => "Lovelace",
             "status" => "trial",
             "active_until" => "2026-10-06T12:00:00.123Z",
             "action" => "create_user"
           }

    assert :ok = CreationWebhookWorker.run(Repo, creation, opts)
    refute_received {:post, _, _, _, _}

    failed_create = %{creation | "event_id" => Ecto.UUID.generate()}

    assert {:error, :manager_transport} =
             CreationWebhookWorker.run(Repo, failed_create,
               env: @env,
               http: fn _, _, _, _ -> {:error, :connection_refused} end
             )

    refute Processed.done?(Repo, failed_create["event_id"])
    assert :ok = CreationWebhookWorker.run(Repo, failed_create, opts)
    assert_receive {:post, _, _, _, nil}

    rows("UPDATE users SET deleted_at=now() WHERE id=$1", [id])

    assert :ok =
             CreationWebhookWorker.run(
               Repo,
               %{creation | "event_id" => Ecto.UUID.generate()},
               opts
             )

    assert :ok =
             CreationWebhookWorker.run(
               Repo,
               %{"user_id" => -1, "event_id" => Ecto.UUID.generate()},
               opts
             )

    refute_received {:post, _, _, _, _}
    assert :ok = DestructionWebhookWorker.run(Repo, destroy, opts)

    assert_receive {:post, "https://manager.example.invalid/api/v1/users/unlink", ^headers,
                    %{"token" => unlink}, 10_000}

    assert decode(unlink) == %{
             "user_id" => id,
             "email" => "snapshot@example.invalid",
             "action" => "destroy_user"
           }

    failed = %{destroy | "event_id" => Ecto.UUID.generate()}

    assert {:error, :manager_transport} =
             DestructionWebhookWorker.run(Repo, failed,
               env: @env,
               http: fn _, _, _, _ -> {:error, :timeout} end
             )

    refute Processed.done?(Repo, failed["event_id"])
    assert :ok = DestructionWebhookWorker.run(Repo, failed, opts)
    assert Processed.done?(Repo, failed["event_id"])
    assert_receive {:post, _, _, _, 10_000}
    assert DestructionWebhookWorker.new(%{}).changes.max_attempts == 5
    assert commands() == []
  end

  @tag a12f3b_case: "E01b"
  test "failed creation transaction cannot publish a webhook" do
    id = user!()
    event = Ecto.UUID.generate()
    Ownership.put!(Repo, "command:users.creation_webhook", :oban)
    assert {:error, :transaction_required} = WebhookCommands.creation(Repo, id, event)

    assert rows("SELECT payload FROM job_outbox WHERE event_id=$1", [Ecto.UUID.dump!(event)]) ==
             []

    assert {:error, :signup_failed} =
             Repo.transaction(fn ->
               assert :ok = WebhookCommands.creation(Repo, id, event)
               Repo.rollback(:signup_failed)
             end)

    assert rows("SELECT payload FROM job_outbox WHERE event_id=$1", [Ecto.UUID.dump!(event)]) ==
             []

    user = Repo.get!(Dawarich.Auth.Account, id, log: false)

    context = %{
      repo: Repo,
      self_hosted: false,
      callbacks: %{
        webhook: fn user_id -> WebhookCommands.creation(Repo, user_id, event) end,
        accept_invitation: fn _, _ -> {:error, :injected} end
      },
      invitation: %{id: 1, email: user.email, acceptable: true}
    }

    assert {:error, :family_owner} =
             Dawarich.Auth.RegistrationSetup.complete(user, %{}, %{}, context)

    assert rows("SELECT payload FROM job_outbox WHERE event_id=$1", [Ecto.UUID.dump!(event)]) ==
             []

    assert {:ok, %{signed_in: false}} =
             Dawarich.Auth.RegistrationSetup.complete(
               user,
               %{},
               %{},
               Map.delete(context, :invitation)
             )

    for _ <- 1..2 do
      assert {:ok, :ok} = Repo.transaction(fn -> WebhookCommands.creation(Repo, id, event) end)
    end

    assert rows("SELECT command_type,payload FROM job_outbox WHERE event_id=$1", [
             Ecto.UUID.dump!(event)
           ]) ==
             [["users.creation_webhook", %{"user_id" => id}]]

    Ownership.put!(Repo, "command:users.creation_webhook", :sidekiq)

    assert {:ok, {:error, :webhook_owner}} =
             Repo.transaction(fn -> WebhookCommands.creation(Repo, id) end)

    Ownership.put!(Repo, "command:users.destruction_webhook", :oban)

    assert {:ok, :ok} =
             Repo.transaction(fn ->
               WebhookCommands.destruction(Repo, id, "saved@example.invalid")
             end)

    assert rows("SELECT payload FROM job_outbox WHERE command_type='users.destruction_webhook'") ==
             [[%{"user_id" => id, "email" => "saved@example.invalid"}]]

    assert commands() == []
  end

  defp email(id), do: rows("SELECT email FROM users WHERE id=$1", [id]) |> hd() |> hd()

  defp decode(token) do
    [header, payload, signature] = String.split(token, ".")
    assert Jason.decode!(Base.url_decode64!(header, padding: false)) == %{"alg" => "HS256"}

    assert Base.url_decode64!(signature, padding: false) ==
             :crypto.mac(:hmac, :sha256, @env["JWT_SECRET_KEY"], header <> "." <> payload)

    Jason.decode!(Base.url_decode64!(payload, padding: false))
  end
end
