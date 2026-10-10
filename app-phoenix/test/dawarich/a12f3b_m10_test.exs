defmodule Dawarich.A12f3bM10Test do
  use Dawarich.JobsCase
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Mail.{LocationRequestWorker, ResidualCommands}

  setup do
    names = ~w(DOMAIN RAILS_ENV)
    previous = Map.take(System.get_env(), names)
    System.put_env(%{"DOMAIN" => "location.example.test", "RAILS_ENV" => "production"})

    on_exit(fn ->
      Enum.each(names, &System.delete_env/1)
      System.put_env(previous)
    end)

    :ok
  end

  defp request! do
    [[requester]] =
      rows(
        "INSERT INTO users(email,settings,created_at,updated_at) VALUES('requester@example.test','{}',now(),now()) RETURNING id"
      )

    [[target]] =
      rows(
        "INSERT INTO users(email,settings,created_at,updated_at) VALUES('target@example.test','{}',now(),now()) RETURNING id"
      )

    [[family]] =
      rows(
        "INSERT INTO families(name,creator_id,created_at,updated_at) VALUES('Family',$1,now(),now()) RETURNING id",
        [requester]
      )

    [[request]] =
      rows(
        "INSERT INTO family_location_requests(requester_id,target_user_id,family_id,status,suggested_duration,expires_at,created_at,updated_at) VALUES($1,$2,$3,0,'24h',now()+interval '1 day',now(),now()) RETURNING id",
        [requester, target, family]
      )

    %{"request_id" => request, "user_id" => requester}
  end

  @tag a12f3b_case: "M10a"
  test "location request native mail preserves failure and sent_at ordering" do
    payload = Map.put(request!(), "locale", "fr")
    assert {:ok, args} = LocationRequestWorker.args_from_command(1, payload)
    args = Map.put(args, "event_id", Ecto.UUID.generate())
    Process.put(:transport_result, {:error, :rejected})
    assert {:error, _} = LocationRequestWorker.perform(%Oban.Job{args: args})
    assert_received {:mail, first}
    assert first.locale == "fr"
    assert rows("SELECT delivered_at FROM phoenix.delivery_claims") == [[nil]]
    Process.delete(:transport_result)
    assert LocationRequestWorker.perform(%Oban.Job{args: args}) == :ok
    assert_received {:mail, second}
    assert first.message_id == second.message_id
    assert rows("SELECT delivered_at IS NOT NULL FROM phoenix.delivery_claims") == [[true]]
  end

  @tag a12f3b_case: "M10b"
  test "location request mail pin OFF preserves source coexistence" do
    payload = request!()
    Ownership.put!(ScratchRepo, "command:mail.family_location_request", :sidekiq)
    assert ResidualCommands.location(ScratchRepo, payload) == :ok

    assert rows("SELECT kind,payload FROM phoenix.rails_commands") == [
             ["family_location_request_mail", payload]
           ]

    assert rows("SELECT count(*) FROM public.job_outbox") == [[0]]
    Ownership.put!(ScratchRepo, "command:mail.family_location_request", :oban)
    assert ResidualCommands.location(ScratchRepo, payload) == :ok
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[1]]
    assert rows("SELECT count(*) FROM public.job_outbox") == [[1]]
    assert ResidualCommands.location(ScratchRepo, payload) == :ok
    assert rows("SELECT count(*) FROM public.job_outbox") == [[1]]
  end
end
