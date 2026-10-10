defmodule Dawarich.A12f3bE02Test do
  use Dawarich.DataCase
  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.Partnero.{CustomerSignup, CustomerSignupWorker}

  @env %{"PARTNERO_API_KEY" => "synthetic-e02-key"}

  @tag a12f3b_case: "E02a"
  test "Partnero signup preserves configured referral and provider behavior" do
    id = user!(%{first_name: "Ada", last_name: "Lovelace"})

    args = %{
      "user_id" => id,
      "partner_key" => "synthetic-partner",
      "event_id" => Ecto.UUID.generate()
    }

    parent = self()

    http = fn url, headers, body, timeout ->
      send(parent, {:signup, url, headers, Jason.decode!(body), timeout})
      {:ok, 200, "ok"}
    end

    opts = [env: @env, http: http]

    assert {:ok, Map.delete(args, "event_id")} ==
             CustomerSignupWorker.args_from_command(1, Map.delete(args, "event_id"))

    assert {:error, "unsupported_version"} == CustomerSignupWorker.args_from_command(2, %{})

    assert {:error, "invalid_payload"} ==
             CustomerSignupWorker.args_from_command(1, %{"user_id" => id, "partner_key" => []})

    for blank <- [nil, "", " \t"] do
      assert {:error, {:cloud_configuration, _}} =
               CustomerSignupWorker.run(Repo, %{args | "event_id" => Ecto.UUID.generate()},
                 env: %{"PARTNERO_API_KEY" => blank},
                 http: http
               )

      assert :ok =
               CustomerSignupWorker.run(
                 Repo,
                 %{args | "partner_key" => blank, "event_id" => Ecto.UUID.generate()},
                 opts
               )
    end

    refute_received {:signup, _, _, _, _}
    assert :ok = CustomerSignupWorker.run(Repo, args, opts)
    assert_receive {:signup, "https://api.partnero.com/v1/customers", headers, payload, 10_000}

    assert headers == [
             {"Authorization", "Bearer synthetic-e02-key"},
             {"Content-Type", "application/json"},
             {"Accept", "application/json"}
           ]

    assert payload == %{
             "partner" => %{"key" => "synthetic-partner"},
             "key" => Integer.to_string(id),
             "email" => email(id),
             "name" => "Ada",
             "surname" => "Lovelace"
           }

    assert :ok = CustomerSignupWorker.run(Repo, args, opts)
    refute_received {:signup, _, _, _, _}
    rows("UPDATE users SET deleted_at=now() WHERE id=$1", [id])

    assert :ok =
             CustomerSignupWorker.run(Repo, %{args | "event_id" => Ecto.UUID.generate()}, opts)

    assert :ok =
             CustomerSignupWorker.run(
               Repo,
               %{args | "user_id" => -1, "event_id" => Ecto.UUID.generate()},
               opts
             )

    refute_received {:signup, _, _, _, _}
    assert commands() == []
  end

  @tag a12f3b_case: "E02b"
  test "Partnero failed provider response remains retryable source behavior" do
    id = user!()
    args = %{"user_id" => id, "partner_key" => "partner", "event_id" => Ecto.UUID.generate()}

    for status <- [401, 422, 500] do
      assert {:error, {:partnero_status, ^status}} =
               CustomerSignupWorker.run(Repo, args,
                 env: @env,
                 http: fn _, _, _, _ -> {:ok, status, "synthetic-e02-key must not escape"} end
               )

      refute Processed.done?(Repo, args["event_id"])
    end

    assert {:error, :partnero_transport} =
             CustomerSignupWorker.run(Repo, args,
               env: @env,
               http: fn _, _, _, _ -> {:error, :timeout} end
             )

    refute Processed.done?(Repo, args["event_id"])

    assert :ok =
             CustomerSignupWorker.run(Repo, args,
               env: @env,
               http: fn _, _, _, _ -> {:ok, 409, "exists"} end
             )

    assert Processed.done?(Repo, args["event_id"])
    assert CustomerSignupWorker.new(%{}).changes.max_attempts == 5
    assert CustomerSignupWorker.backoff(%Oban.Job{attempt: 2}) in 18..20

    Ownership.put!(Repo, "command:partnero.customer_signup", :oban)
    event = Ecto.UUID.generate()
    assert {:error, :transaction_required} = CustomerSignup.enqueue(Repo, id, "partner", event)

    assert {:error, :signup_failed} =
             Repo.transaction(fn ->
               assert :ok = CustomerSignup.enqueue(Repo, id, "partner", event)
               Repo.rollback(:signup_failed)
             end)

    assert rows("SELECT payload FROM job_outbox WHERE event_id=$1", [Ecto.UUID.dump!(event)]) ==
             []

    for _ <- 1..2 do
      assert {:ok, %{}} =
               Repo.transaction(fn ->
                 Dawarich.Auth.RegistrationAttribution.apply(
                   Repo,
                   Repo.get!(Dawarich.Auth.Account, id, log: false),
                   %{},
                   %{"partnero_referral" => "partner"},
                   %{
                     callbacks: %{
                       partnero: fn user_id, partner ->
                         CustomerSignup.enqueue(Repo, user_id, partner, event)
                       end
                     }
                   }
                 )
               end)
    end

    assert rows("SELECT command_type,payload FROM job_outbox WHERE event_id=$1", [
             Ecto.UUID.dump!(event)
           ]) ==
             [["partnero.customer_signup", %{"user_id" => id, "partner_key" => "partner"}]]

    Ownership.put!(Repo, "command:partnero.customer_signup", :sidekiq)

    assert {:ok, {:error, :partnero_owner}} =
             Repo.transaction(fn -> CustomerSignup.enqueue(Repo, id, "partner") end)

    assert commands() == []
  end

  defp email(id), do: rows("SELECT email FROM users WHERE id=$1", [id]) |> hd() |> hd()
end
