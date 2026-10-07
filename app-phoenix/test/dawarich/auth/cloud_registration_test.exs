defmodule Dawarich.Auth.CloudRegistrationTest do
  use Dawarich.JobsCase
  alias Dawarich.Auth.Registration
  alias Dawarich.Jobs.Ownership

  test "L1 registration callback failure cannot leave an account without durable creation intent" do
    source =
      File.read!(Path.expand("../../fixtures/cloud_creation/source.json", __DIR__))
      |> Jason.decode!()

    assert source["failure"]["account_persisted_without_callback"]

    context = %{
      repo: ScratchRepo,
      self_hosted: false,
      log_rounds: 4,
      env: %{"SELF_HOSTED" => "false"},
      callbacks: %{webhook: fn _ -> {:error, :injected_publication_failure} end}
    }

    params = %{
      "email" => "atomic@example.invalid",
      "password" => "synthetic-password",
      "password_confirmation" => "synthetic-password"
    }

    assert {:error, :injected_publication_failure} = Registration.create(params, context)
    assert rows("SELECT count(*) FROM users WHERE email='atomic@example.invalid'") == [[0]]
    assert rows("SELECT count(*) FROM job_outbox") == [[0]]
    assert rows("SELECT count(*) FROM phoenix.processed_commands") == [[0]]
    Ownership.put!(ScratchRepo, "command:users.creation_webhook", :oban)
    context = Map.delete(context, :callbacks)
    assert {:ok, user} = Registration.create(params, context)
    assert rows("SELECT count(*) FROM job_outbox WHERE aggregate_id=$1", [user.id]) == [[1]]

    failing =
      context
      |> Map.put(:registration_channel, :mobile)
      |> Map.put(:callbacks, %{partnero: fn _, _ -> {:error, :fault_after_intent} end})

    assert {:error, :partnero_owner} =
             Registration.register(
               Map.put(params, "email", "late-failure@example.invalid"),
               %{"partnero_referral" => "synthetic-partner"},
               failing
             )

    assert rows("SELECT count(*) FROM users WHERE email='late-failure@example.invalid'") == [[0]]
    assert rows("SELECT count(*) FROM job_outbox") == [[1]]

    assert rows(
             "SELECT count(*) FROM phoenix.processed_commands WHERE handler='users.creation_effects'"
           ) == [[1]]

    assert {:error, %{errors: _}} = Registration.create(params, context)

    assert {:error, %{errors: _}} =
             Registration.create(Map.put(params, "password", "short"), context)

    assert rows("SELECT count(*) FROM job_outbox") == [[1]]

    assert {:error, :denied} =
             Registration.create(Map.put(params, "email", "denied@example.invalid"), %{
               context
               | self_hosted: true
             })

    assert rows("SELECT count(*) FROM users") == [[1]]
  end
end
