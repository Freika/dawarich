defmodule Dawarich.Auth.AccountLink.SignInTest do
  use ExUnit.Case, async: false
  alias Dawarich.Auth.AccountLink.{Confirmation, SignIn}
  alias Dawarich.{Auth.Account, Repo, Test.RailsUser}

  @source "test/fixtures/auth/account_link/requests.json" |> File.read!() |> Jason.decode!()
  @now ~U[2026-10-05 12:00:00.000000Z]
  @owned [
    {911_452_001, "a11e-sign-in-1@example.invalid"},
    {911_452_002, "a11e-sign-in-2@example.invalid"},
    {911_452_003, "a11e-sign-in-3@example.invalid"}
  ]

  defmodule TrackableFailureRepo do
    def update!(changeset, opts) do
      if Map.has_key?(changeset.changes, :sign_in_count), do: raise("a11e-trackable-failure")
      Dawarich.Repo.update!(changeset, opts)
    end
  end

  defp context, do: %{self_hosted: true, oidc: true, clock: fn -> @now end, ip: "198.51.100.231"}

  defp session(id) do
    pending = @source["challenge_en"]["session"]

    pending
    |> put_in(["pending_oauth_link", "user_id"], id)
    |> put_in(["pending_oauth_link", "uid"], "a11e-sign-in-#{id}")
  end

  defp observe(id, writer_pid) do
    Task.async(fn ->
      Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
        [[pid]] = Repo.query!("SELECT pg_backend_pid()", [], log: false).rows
        refute pid == writer_pid
        refute Repo.in_transaction?()
        Repo.get!(Account, id)
      end)
    end)
    |> Task.await()
  end

  test "default account-link sign-in matches source callbacks and preserves earlier saves on later failure" do
    assert Code.ensure_loaded?(SignIn)

    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      for {id, email} <- @owned do
        refute Repo.exists?(from_user(id, email))
      end

      try do
        for {id, email} <- @owned do
          RailsUser.insert!(%{
            id: id,
            email: email,
            encrypted_password: @source["challenge_en"]["before"]["encrypted_password"],
            settings: %{},
            provider: nil,
            uid: nil,
            failed_attempts: 2,
            sign_in_count: 0,
            failed_otp_attempts: 3,
            consumed_timestep: 42,
            otp_locked_at: ~N[2026-10-05 11:59:00],
            unlock_token: "a11e-unlock-#{id}",
            remember_created_at: ~N[2026-10-04 12:00:00]
          })
        end

        [[writer_pid]] = Repo.query!("SELECT pg_backend_pid()", [], log: false).rows
        other = Repo.get!(Account, 911_452_003)

        assert {:ok, prepared} =
                 Confirmation.prepare(session(911_452_001), "safepassword12", context())

        assert {:ok, linked} = Confirmation.commit(prepared, context())
        assert {:ok, result} = SignIn.commit(linked, context())
        observed = observe(linked.user.id, writer_pid)
        assert observed.provider == "openid_connect"
        assert observed.uid == linked.pending["uid"]
        assert observed.sign_in_count == @source["success_en"]["after"]["sign_in_count"]
        assert observed.failed_attempts == @source["success_en"]["after"]["failed_attempts"]
        assert observed.current_sign_in_at == @now
        assert observed.last_sign_in_at == @now
        assert observed.current_sign_in_ip == "198.51.100.231"
        assert observed.last_sign_in_ip == "198.51.100.231"
        assert observed.remember_created_at == linked.user.remember_created_at
        assert observed.failed_otp_attempts == 3
        assert observed.otp_locked_at == linked.user.otp_locked_at
        assert observed.consumed_timestep == 42
        assert observed.unlock_token == linked.user.unlock_token
        assert observed.locked_at == nil
        assert result.session == linked.session

        assert Map.delete(Map.from_struct(result.user), :settings) ==
                 Map.delete(Map.from_struct(observed), :settings)

        assert Repo.get!(Account, other.id) == other

        user = Repo.get!(Account, 911_452_002)
        user |> Ecto.Changeset.change(otp_required_for_login: true) |> Repo.update!(log: false)

        assert {:ok, prepared} =
                 Confirmation.prepare(session(user.id), "safepassword12", context())

        assert {:ok, link_only} = Confirmation.commit(prepared, context())
        before = Repo.get!(Account, user.id)
        assert {:ok, ^link_only} = SignIn.commit(link_only, context())
        assert observe(user.id, writer_pid) == before

        assert {:ok, prepared} =
                 Confirmation.prepare(session(other.id), "safepassword12", context())

        assert {:ok, linked} = Confirmation.commit(prepared, context())
        failure = Map.put(context(), :repo, TrackableFailureRepo)

        assert_raise RuntimeError, "a11e-trackable-failure", fn ->
          SignIn.commit(linked, failure)
        end

        durable = observe(other.id, writer_pid)
        source = @source["later_callback_failure"]["durable"]
        assert durable.provider == source["provider"]
        assert durable.uid == linked.pending["uid"]
        assert durable.sign_in_count == source["sign_in_count"]
        assert durable.failed_attempts == source["failed_attempts"]
        assert durable.failed_otp_attempts == 3
        assert durable.remember_created_at == other.remember_created_at
      after
        for {id, email} <- @owned do
          Repo.delete_all(from_user(id, email))
        end
      end
    end)
  end

  defp from_user(id, email) do
    import Ecto.Query
    from(u in Account, where: u.id == ^id and u.email == ^email)
  end
end
