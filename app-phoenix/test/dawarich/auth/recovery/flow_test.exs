defmodule Dawarich.Auth.Recovery.FlowTest do
  use ExUnit.Case, async: true
  alias Dawarich.Auth.Recovery.{Flow, Lifecycle, Token}
  alias Dawarich.Repo
  @secret "phoenix-a2-cookie-fixture-secret-not-for-production"
  @now ~U[2026-10-01 12:00:00.000000Z]
  @http Jason.decode!(
          File.read!(Path.expand("../../../fixtures/auth/recovery/http.json", __DIR__))
        )
  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    email = "flow-#{System.unique_integer([:positive])}@dawarich.test"

    [[id]] =
      Repo.query!(
        "INSERT INTO users(email,status,otp_required_for_login,created_at,updated_at) VALUES($1,1,true,$2,$2) RETURNING id",
        [email, @now]
      ).rows

    owner = self()

    context = %{
      enabled: true,
      self_hosted: true,
      oidc: false,
      headers: [],
      locale: "en",
      secret: @secret,
      clock: fn -> @now end,
      log_rounds: 4,
      sign_in_ip: "192.0.2.10",
      enqueue: fn intent ->
        send(owner, {:intent, intent})
        :ok
      end
    }

    %{id: id, email: email, context: context}
  end

  test "missing-token GET and known/unknown request match actual HTTP statuses and flashes", c do
    assert {:ok, r} = Flow.dispatch("GET", "/users/password/edit", %{}, %{}, c.context)
    assert r.status == @http["missing_token_edit"]["status"]
    assert r.location == "/users/sign_in"

    for email <- [c.email, "unknown@dawarich.test"] do
      assert {:ok, r} =
               Flow.dispatch("POST", "/users/password", %{"user[email]" => email}, %{}, c.context)

      assert r.status == @http["known_request"]["status"]
      assert r.session["flash"]["flashes"] == @http["known_request"]["flash"]["flashes"]
    end

    assert_received {:intent, _}
    refute_received {:intent, _}
  end

  test "actual reset auto-sign-in rotates Rails session and records Trackable once", c do
    {:ok, %{notification: intent}} = Lifecycle.request_reset(c.email, c.context)
    old = %{"session_id" => "old-id", "_csrf_token" => "old-csrf"}

    params = %{
      "user[reset_password_token]" => intent.raw,
      "user[password]" => "newpassword12345",
      "user[password_confirmation]" => "newpassword12345"
    }

    assert {:ok, r} = Flow.dispatch("PUT", "/users/password", params, old, c.context)
    assert r.status == @http["otp_success_reset"]["status"]
    assert r.location == "/"
    id = c.id
    assert [[^id], salt] = r.session["warden.user.user.key"]
    assert byte_size(salt) == 29
    refute r.session["session_id"] == "old-id"
    refute Map.has_key?(r.session, "_csrf_token")

    [[count, ip]] =
      Repo.query!("SELECT sign_in_count,current_sign_in_ip FROM users WHERE id=$1", [c.id]).rows

    assert count == 1 and ip == "192.0.2.10"
    assert {:ok, replay} = Flow.dispatch("PUT", "/users/password", params, %{}, c.context)
    assert replay.status == 422
    refute Map.has_key?(replay.session, "warden.user.user.key")
  end

  test "actual unlock GET success never signs in and replay renders 200", c do
    digest = Token.digest(:unlock_token, "unlock", @secret)
    Repo.query!("UPDATE users SET unlock_token=$1,locked_at=$2 WHERE id=$3", [digest, @now, c.id])

    assert {:ok, r} =
             Flow.dispatch("GET", "/users/unlock", %{"unlock_token" => "unlock"}, %{}, c.context)

    assert r.status == @http["success_unlock"]["status"]
    refute Map.has_key?(r.session, "warden.user.user.key")

    assert {:ok, r} =
             Flow.dispatch("GET", "/users/unlock", %{"unlock_token" => "unlock"}, %{}, c.context)

    assert r.status == @http["replay_unlock"]["status"]
  end

  test "inactive or special contexts hand back before token issuance", c do
    assert {:handoff, _} =
             Flow.dispatch(
               "POST",
               "/users/password",
               %{"user[email]" => c.email},
               %{},
               Map.put(c.context, :enabled, false)
             )

    assert {:handoff, _} =
             Flow.dispatch(
               "POST",
               "/users/password",
               %{"user[email]" => c.email},
               %{"invitation_token" => "special"},
               c.context
             )

    [[token]] = Repo.query!("SELECT reset_password_token FROM users WHERE id=$1", [c.id]).rows
    assert token == nil
    refute_received {:intent, _}
  end

  test "a context without an enabled flag hands back before token issuance", c do
    assert {:handoff, _} =
             Flow.dispatch(
               "POST",
               "/users/password",
               %{"user[email]" => c.email},
               %{},
               Map.delete(c.context, :enabled)
             )

    [[token]] = Repo.query!("SELECT reset_password_token FROM users WHERE id=$1", [c.id]).rows
    assert token == nil
    refute_received {:intent, _}
  end

  test "three actual unlock request states share the source paranoid response", c do
    for {email, key, locked} <- [
          {c.email, "locked_unlock_request", true},
          {c.email, "unlocked_unlock_request", false},
          {"unknown@dawarich.test", "unknown_unlock_request", false}
        ] do
      Repo.query!("UPDATE users SET locked_at=$1 WHERE id=$2", [
        if(locked, do: @now, else: nil),
        c.id
      ])

      assert {:ok, r} =
               Flow.dispatch("POST", "/users/unlock", %{"user[email]" => email}, %{}, c.context)

      assert r.status == @http[key]["status"]
      assert r.session["flash"] == @http[key]["flash"]
    end

    assert_received {:intent, _}
    refute_received {:intent, _}
  end
end
