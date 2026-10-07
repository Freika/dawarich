defmodule Dawarich.Partnero.CloudSignupTest do
  use Dawarich.JobsCase, async: false
  import ExUnit.CaptureLog
  import Dawarich.AnomalyCase
  alias Dawarich.AfterCommit
  alias Dawarich.Auth.{Account, RegistrationAttribution}
  alias Dawarich.Jobs.{Dispatch, Ownership, Processed, Registry}
  alias Dawarich.Partnero.{CustomerSignup, CustomerSignupWorker}

  @oban Dawarich.PartneroCloudSignupOban
  @env %{"PARTNERO_API_KEY" => "synthetic-l1-key"}

  setup do
    start_oban(@oban)
    Ownership.put!(ScratchRepo, "command:partnero.customer_signup", :oban)
    user = user!()
    rows("UPDATE users SET first_name='Ada',last_name='Lovelace' WHERE id=$1", [user])
    %{user: user}
  end

  @tag l1_d: :payload
  test "L1 configured Partnero signup dispatches real source-equivalent customer payload", ctx do
    event = Ecto.UUID.generate()
    parent = self()

    transport = fn method, origin, path, headers, body, insecure, timeout, opts ->
      refute ScratchRepo.in_transaction?()
      assert method == :post
      assert origin == "https://api.partnero.com"
      assert path == "/v1/customers"
      assert insecure == false
      assert timeout == 10_000 and opts[:total_timeout] == 10_000
      assert Enum.into(headers, %{})["Authorization"] == "Bearer " <> @env["PARTNERO_API_KEY"]
      assert Enum.into(headers, %{})["Content-Type"] == "application/json"
      assert Enum.into(headers, %{})["Accept"] == "application/json"
      send(parent, {:customer, Jason.decode!(body)})
      {:ok, 201, [], ""}
    end

    assert {:error, :transaction_required} =
             CustomerSignup.enqueue(ScratchRepo, ctx.user, "synthetic-partner", event)

    assert {:error, :cancel} =
             ScratchRepo.transaction(fn ->
               assert :ok =
                        CustomerSignup.enqueue(ScratchRepo, ctx.user, "synthetic-partner", event)

               assert Task.await(
                        Task.async(fn -> rows("SELECT count(*) FROM public.job_outbox") end)
                      ) == [[0]]

               ScratchRepo.rollback(:cancel)
             end)

    assert rows("SELECT count(*) FROM public.job_outbox") == [[0]]

    assert {:ok, :ok} =
             ScratchRepo.transaction(fn ->
               CustomerSignup.enqueue(ScratchRepo, ctx.user, "synthetic-partner", event)
             end)

    refute_received {:customer, _}
    assert Registry.command("partnero.customer_signup") == {:ok, CustomerSignupWorker}

    assert Dispatch.run(repo: ScratchRepo, oban: @oban, now: db_now(ScratchRepo)) == %{
             dispatched: 1
           }

    [[args]] = rows("SELECT args FROM oban.oban_jobs")
    assert args["event_id"] == event

    assert :ok =
             CustomerSignupWorker.run(ScratchRepo, args,
               env: @env,
               transport: transport,
               http: fn _, _, _, _ ->
                 refute ScratchRepo.in_transaction?()
                 flunk("shared transport required")
               end
             )

    assert_receive {:customer, payload}
    [[email]] = rows("SELECT email FROM users WHERE id=$1", [ctx.user])

    assert payload == %{
             "partner" => %{"key" => "synthetic-partner"},
             "key" => Integer.to_string(ctx.user),
             "email" => email,
             "name" => "Ada",
             "surname" => "Lovelace"
           }

    assert Processed.done?(ScratchRepo, event)

    assert :ok =
             CustomerSignupWorker.run(ScratchRepo, args,
               env: @env,
               transport: transport,
               http: fn _, _, _, _ ->
                 refute ScratchRepo.in_transaction?()
                 flunk("shared transport required")
               end
             )

    refute_received {:customer, _}
  end

  @tag l1_d: :referral
  test "L1 Partnero referral is consumed once with Rails precedence and Unicode boundaries",
       ctx do
    referral = String.duplicate("ф", 400)
    session = RegistrationAttribution.store(%{}, %{"aff" => referral, "via" => "losing-key"})
    assert session["partnero_referral"] == String.duplicate("ф", 255)
    user = ScratchRepo.get!(Account, ctx.user, log: false)

    context = %{
      callbacks: %{partnero: fn id, key -> CustomerSignup.enqueue(ScratchRepo, id, key) end}
    }

    Ownership.put!(ScratchRepo, "command:partnero.customer_signup", :sidekiq)

    assert {:error, :partnero_owner} =
             ScratchRepo.transaction(fn ->
               RegistrationAttribution.apply(ScratchRepo, user, %{}, session, context)
             end)

    assert Map.has_key?(session, "partnero_referral")
    assert rows("SELECT count(*) FROM public.job_outbox") == [[0]]
    Ownership.put!(ScratchRepo, "command:partnero.customer_signup", :oban)

    assert {:ok, spent} =
             ScratchRepo.transaction(fn ->
               RegistrationAttribution.apply(ScratchRepo, user, %{}, session, context)
             end)

    refute Map.has_key?(spent, "partnero_referral")
    second = ScratchRepo.get!(Account, user!(), log: false)

    assert {:ok, ^spent} =
             ScratchRepo.transaction(fn ->
               RegistrationAttribution.apply(ScratchRepo, second, %{}, spent, context)
             end)

    assert rows("SELECT aggregate_id FROM public.job_outbox") == [[ctx.user]]

    assert {:ok, :ok} =
             ScratchRepo.transaction(fn ->
               CustomerSignup.enqueue(ScratchRepo, ctx.user, session["partnero_referral"])
             end)

    assert rows("SELECT count(*) FROM public.job_outbox") == [[1]]
    [[event]] = rows("SELECT event_id FROM public.job_outbox")
    event = Ecto.UUID.load!(event)
    assert event == AfterCommit.identity(ctx.user, "partnero.customer_signup")

    assert :ok =
             CustomerSignupWorker.run(
               ScratchRepo,
               %{
                 "user_id" => ctx.user,
                 "partner_key" => session["partnero_referral"],
                 "event_id" => event
               },
               env: @env,
               transport: fn _, _, _, _, _, _, _, _ -> {:ok, 201, [], ""} end
             )

    rows("DELETE FROM public.job_outbox")

    assert {:ok, :ok} =
             ScratchRepo.transaction(fn ->
               CustomerSignup.enqueue(ScratchRepo, ctx.user, "later-key")
             end)

    assert rows("SELECT count(*) FROM public.job_outbox") == [[0]]

    tasks =
      for _ <- 1..2 do
        Task.async(fn ->
          ScratchRepo.transaction(fn ->
            CustomerSignup.enqueue(ScratchRepo, second.id, "second-key")
          end)
        end)
      end

    for task <- tasks, do: assert(Task.await(task) == {:ok, :ok})
    assert rows("SELECT count(*) FROM public.job_outbox") == [[1]]
  end

  @tag l1_d: :retry
  test "L1 Partnero accepts 409 retries rejection and suppresses accepted-send replay", ctx do
    event = Ecto.UUID.generate()
    args = %{"user_id" => ctx.user, "partner_key" => "synthetic-partner", "event_id" => event}
    parent = self()

    forbidden = fn _, _, _, _, _, _, _, _ ->
      send(parent, :forbidden_http)
      {:ok, 200, [], ""}
    end

    assert {:ok, {:error, :transaction_required}} =
             ScratchRepo.transaction(fn ->
               CustomerSignup.call(ScratchRepo, ctx.user, args["partner_key"],
                 env: @env,
                 transport: forbidden
               )
             end)

    refute_received :forbidden_http

    assert {:ok, {:error, :transaction_required}} =
             ScratchRepo.transaction(fn ->
               CustomerSignupWorker.run(ScratchRepo, args, env: @env, transport: forbidden)
             end)

    refute Processed.done?(ScratchRepo, event)

    logs =
      capture_log(fn ->
        for status <- [302, 401, 422, 500, 503] do
          assert {:error, {:partnero_status, ^status}} =
                   CustomerSignupWorker.run(ScratchRepo, args,
                     env: @env,
                     transport: fn _, _, _, _, _, _, _, _ ->
                       {:ok, status, [], "synthetic-sensitive-response"}
                     end
                   )

          refute Processed.done?(ScratchRepo, event)
        end

        for failure <- [:timeout, :connect_timeout, :connection] do
          assert {:error, :partnero_transport} =
                   CustomerSignupWorker.run(ScratchRepo, args,
                     env: @env,
                     transport: fn _, _, _, _, _, _, _, _ -> {:error, failure} end
                   )

          refute Processed.done?(ScratchRepo, event)
        end

        assert {:error, :partnero_transport} =
                 CustomerSignupWorker.run(ScratchRepo, args,
                   env: @env,
                   transport: fn _, _, _, _, _, _, _, _ ->
                     raise "synthetic-sensitive-exception"
                   end
                 )

        refute Processed.done?(ScratchRepo, event)
      end)

    refute logs =~ @env["PARTNERO_API_KEY"]
    refute logs =~ "synthetic-sensitive"

    for status <- [200, 201, 204, 299, 409] do
      accepted = %{args | "event_id" => Ecto.UUID.generate()}
      opts = [env: @env, transport: fn _, _, _, _, _, _, _, _ -> {:ok, status, [], ""} end]
      assert :ok = CustomerSignupWorker.run(ScratchRepo, accepted, opts)
      assert Processed.done?(ScratchRepo, accepted["event_id"])

      assert :ok =
               CustomerSignupWorker.run(ScratchRepo, accepted, env: @env, transport: forbidden)
    end

    refute_received :forbidden_http
    assert CustomerSignupWorker.new(%{}).changes.max_attempts == 5

    provider = start_supervised!({Agent, fn -> MapSet.new() end})

    transport = fn _, _, _, _, body, _, _, _ ->
      customer = Jason.decode!(body)["key"]
      assert customer == Integer.to_string(ctx.user)

      exists =
        Agent.get_and_update(provider, fn keys ->
          {MapSet.member?(keys, customer), MapSet.put(keys, customer)}
        end)

      if exists do
        send(parent, {:replayed_customer, customer})
        {:ok, 409, [], ""}
      else
        send(parent, {:accepted_customer, self()})

        receive do
          :ack -> {:ok, 201, [], ""}
        end
      end
    end

    {pid, monitor} =
      spawn_monitor(fn ->
        CustomerSignupWorker.run(ScratchRepo, args, env: @env, transport: transport)
      end)

    assert_receive {:accepted_customer, ^pid}
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}
    refute Processed.done?(ScratchRepo, event)
    assert :ok = CustomerSignupWorker.run(ScratchRepo, args, env: @env, transport: transport)
    assert_receive {:replayed_customer, _}
    assert Agent.get(provider, &MapSet.size/1) == 1
    assert Processed.done?(ScratchRepo, event)

    for blank <- [nil, "", " \t"] do
      assert {:error, {:cloud_configuration, _}} =
               CustomerSignupWorker.run(ScratchRepo, %{args | "event_id" => Ecto.UUID.generate()},
                 env: %{"PARTNERO_API_KEY" => blank},
                 transport: forbidden
               )

      assert :ok =
               CustomerSignupWorker.run(
                 ScratchRepo,
                 %{args | "partner_key" => blank, "event_id" => Ecto.UUID.generate()},
                 env: @env,
                 transport: forbidden
               )
    end

    assert :ok =
             CustomerSignupWorker.run(
               ScratchRepo,
               %{args | "user_id" => -1, "event_id" => Ecto.UUID.generate()},
               env: @env,
               transport: forbidden
             )

    rows("UPDATE users SET deleted_at=now() WHERE id=$1", [ctx.user])

    assert :ok =
             CustomerSignupWorker.run(
               ScratchRepo,
               %{args | "event_id" => Ecto.UUID.generate()},
               env: @env,
               transport: forbidden
             )

    refute_received :forbidden_http
  end
end
