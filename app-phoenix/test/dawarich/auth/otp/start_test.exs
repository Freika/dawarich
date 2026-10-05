defmodule Dawarich.Auth.Otp.StartTest do
  use ExUnit.Case, async: false
  alias Dawarich.Auth.{Account, Otp.Start}
  alias Dawarich.{Repo, Test.RailsUser}

  @source "test/fixtures/auth/requests.json" |> File.read!() |> Jason.decode!()
  @crypto "test/fixtures/active_record_encryption.json" |> File.read!() |> Jason.decode!()
  @env Enum.find(@crypto["environments"], &(&1["name"] == "explicit keys"))["env"]
  @now ~U[2026-10-04 12:00:00.000000Z]
  @id 75_500
  @email "a11d-start@dawarich.test"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    RailsUser.insert!(%{
      id: @id,
      email: @email,
      encrypted_password: @source["login"]["user"]["encrypted_password"],
      otp_required_for_login: true,
      failed_attempts: 2,
      failed_otp_attempts: 3,
      sign_in_count: 7,
      api_key: "A11D_START",
      settings: %{}
    })

    %{context: %{self_hosted: true, oidc: false, env: @env, clock: fn -> @now end, remember: "1"}}
  end

  defp snapshot do
    Repo.query!("SELECT to_jsonb(u) FROM users u ORDER BY id", [], log: false).rows
  end

  defp seed(values),
    do: Repo.get!(Account, @id) |> Ecto.Changeset.change(values) |> Repo.update!(log: false)

  test "OTP start uses exact source lookup and creates no login effects", c do
    assert Code.ensure_loaded?(Start)

    session = %{
      "_csrf_token" => "synthetic-csrf",
      "otp_failed_attempts" => 2,
      "user_return_to" => "/trips"
    }

    before = snapshot()

    assert {:challenge, user, pending} =
             Start.prepare(@email, "safepassword12", session, c.context)

    assert user.id == @id

    assert pending ==
             Map.merge(session, %{
               "otp_user_id" => @id,
               "otp_challenge_at" => DateTime.to_unix(@now),
               "otp_remember_me" => true
             })

    refute Map.has_key?(pending, "warden.user.user.key")
    assert snapshot() == before

    for email <- [String.upcase(@email), " #{@email} "] do
      assert match?({:handoff, _}, Start.prepare(email, "safepassword12", session, c.context))
      assert snapshot() == before
    end

    for password <- ["wrong", "", nil, [], "safepassword12" <> <<0>>] do
      assert match?({:handoff, _}, Start.prepare(@email, password, session, c.context))
      assert snapshot() == before
    end

    for values <- [
          [provider: "github"],
          [status: 3],
          [locked_at: DateTime.add(@now, -60)],
          [locked_at: DateTime.add(@now, -7200)],
          [deleted_at: @now],
          [settings: %{"immich_url" => "https://synthetic.invalid/"}],
          [settings: %{"maps" => 1}]
        ] do
      initial = Repo.get!(Account, @id)
      [[settings]] = Repo.query!("SELECT settings FROM users WHERE id=$1", [@id], log: false).rows
      initial = %{initial | settings: settings}
      seed(values)
      before = snapshot()
      assert match?({:handoff, _}, Start.prepare(@email, "safepassword12", session, c.context))
      assert snapshot() == before
      seed(Map.new(values, fn {key, _} -> {key, Map.fetch!(initial, key)} end))
    end

    for context <- [
          %{c.context | self_hosted: false},
          %{c.context | oidc: true},
          %{c.context | env: %{}}
        ] do
      before = snapshot()
      assert match?({:handoff, _}, Start.prepare(@email, "safepassword12", session, context))
      assert snapshot() == before
    end

    assert {:challenge, _, _} = Start.prepare(@email, "safepassword12", session, c.context)

    seed(otp_required_for_login: false)
    before = snapshot()
    assert Start.prepare(@email, "wrong", session, c.context) == :ordinary
    assert Start.prepare("unknown@dawarich.test", "wrong", session, c.context) == :ordinary
    assert snapshot() == before
  end
end
