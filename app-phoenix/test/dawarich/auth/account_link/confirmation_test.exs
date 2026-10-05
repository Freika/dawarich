defmodule Dawarich.Auth.AccountLink.ConfirmationTest do
  use ExUnit.Case, async: false
  alias Dawarich.Auth.AccountLink.Confirmation
  alias Dawarich.{Repo, Test.RailsUser}

  @source "test/fixtures/auth/account_link/requests.json" |> File.read!() |> Jason.decode!()
  @now DateTime.from_unix!(@source["at"] * 1_000_000, :microsecond)
  defp context, do: %{self_hosted: true, oidc: true, clock: fn -> @now end}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  defp actor(state, hash) do
    RailsUser.insert!(%{
      id: state["id"],
      email: state["email"],
      encrypted_password: hash,
      provider: nil,
      uid: nil,
      settings: %{},
      status: 1,
      failed_attempts: state["failed_attempts"],
      failed_otp_attempts: state["failed_otp_attempts"],
      consumed_timestep: state["consumed_timestep"],
      sign_in_count: state["sign_in_count"],
      otp_required_for_login: state["otp_required_for_login"],
      remember_created_at: ~N[2026-10-04 12:00:00]
    })
  end

  defp session(id) do
    source = @source["challenge_en"]["session"]

    source
    |> put_in(["pending_oauth_link", "user_id"], id)
    |> put_in(["pending_oauth_link", "uid"], "a11e-sub-#{id}-A")
  end

  defp snapshot do
    Repo.query!("SELECT to_jsonb(u) FROM users u ORDER BY id", [], log: false).rows
  end

  test "password confirmation preflight never creates effects on Rails-owned cases" do
    assert Code.ensure_loaded?(Confirmation)
    state = @source["challenge_en"]["before"]
    actor(state, state["encrypted_password"])
    pending = session(state["id"])
    before = snapshot()
    assert {:ok, prepared} = Confirmation.prepare(pending, "safepassword12", context())
    assert prepared.user.id == state["id"]
    assert prepared.session == pending
    assert prepared.user.provider == nil
    assert prepared.user.uid == nil
    assert snapshot() == before

    for password <- [
          "wrong",
          nil,
          "",
          "   ",
          "SAFEPASSWORD12",
          "safepassword12" <> <<0>>,
          [],
          %{},
          <<255>>
        ] do
      assert {:handoff, _} = Confirmation.prepare(pending, password, context())
      assert snapshot() == before
      assert pending == session(state["id"])
    end

    for field <- [:encrypted_password, :uid, :provider, :settings] do
      changes =
        case field do
          :encrypted_password -> %{encrypted_password: "invalid-bcrypt"}
          :uid -> %{uid: "a11e-partial-identity"}
          :provider -> %{provider: "openid_connect"}
          :settings -> %{settings: %{"immich_url" => "https://example.invalid/"}}
        end

      initial =
        Repo.query!("SELECT #{field} FROM users WHERE id=$1", [state["id"]], log: false).rows

      user = Repo.get!(Dawarich.Auth.Account, state["id"])
      user |> Ecto.Changeset.change(changes) |> Repo.update!(log: false)
      before = snapshot()
      assert {:handoff, _} = Confirmation.prepare(pending, "safepassword12", context())
      assert snapshot() == before
      [[value]] = initial
      user |> Ecto.Changeset.change(Map.put(%{}, field, value)) |> Repo.update!(log: false)
    end
  end

  test "password byte boundary matches recorded Rails Devise vectors" do
    assert Code.ensure_loaded?(Confirmation)

    for vector <- @source["password_vectors"] do
      state = vector["confirmation"]["before"]
      actor(state, vector["hash"])
      before = snapshot()
      pending = session(state["id"])
      password = vector["password"]
      assert byte_size(password || "") == vector["bytes"]
      result = Confirmation.prepare(pending, password, context())

      if vector["native"] and vector["valid_password"] == true do
        assert {:ok, prepared} = result
        assert prepared.user.encrypted_password == vector["hash"]
        assert prepared.session == pending
      else
        assert {:handoff, _} = result
      end

      assert snapshot() == before
      assert pending == session(state["id"])
    end
  end

  test "identity save precedes pending clear and OTP link-only never authenticates" do
    for name <- ~w(success_en otp) do
      oracle = @source[name]
      state = oracle["before"]
      actor(state, state["encrypted_password"])
      pending = session(state["id"])
      assert {:ok, prepared} = Confirmation.prepare(pending, "safepassword12", context())

      before =
        Repo.query!("SELECT to_jsonb(u) FROM users u WHERE id=$1", [state["id"]], log: false).rows

      assert {:ok, saved} = Confirmation.commit(prepared, context())
      assert saved.kind == if(name == "otp", do: :link_only, else: :sign_in)
      assert saved.user.provider == "openid_connect"
      assert saved.user.uid == pending["pending_oauth_link"]["uid"]

      assert saved.session ==
               Map.drop(pending, ~w(pending_oauth_link pending_oauth_link_attempts))

      refute Map.has_key?(saved.session, "warden.user.user.key")
      assert saved.user.updated_at == @now

      [[after_row]] =
        Repo.query!("SELECT to_jsonb(u) FROM users u WHERE id=$1", [state["id"]], log: false).rows

      [[before_row]] = before
      changed = ~w(provider uid updated_at)
      assert Map.drop(after_row, changed) == Map.drop(before_row, changed)
      assert pending == session(state["id"])
    end

    invalid = put_in(session(999_999_999), ["pending_oauth_link", "user_id"], 999_999_999)
    assert {:handoff, _} = Confirmation.prepare(invalid, "safepassword12", context())
    state = @source["unique_conflict"]["before"]
    actor(state, state["encrypted_password"])
    pending = session(state["id"])
    assert {:ok, prepared} = Confirmation.prepare(pending, "safepassword12", context())

    RailsUser.insert!(%{
      id: state["id"] + 10_000,
      email: "a11e-unique@example.invalid",
      provider: "openid_connect",
      uid: pending["pending_oauth_link"]["uid"]
    })

    before = snapshot()
    assert_raise Ecto.ConstraintError, fn -> Confirmation.commit(prepared, context()) end
    assert snapshot() == before
    assert prepared.session == pending
    assert prepared.user.provider == nil
    assert prepared.user.uid == nil
  end
end
