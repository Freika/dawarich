defmodule Dawarich.Auth.SessionProtocolTest do
  use ExUnit.Case, async: true
  alias Dawarich.Auth.{ActionCsrf, SessionCookie}
  alias Dawarich.RailsCookies

  @fixture Jason.decode!(File.read!(Path.expand("../../fixtures/auth/requests.json", __DIR__)))
  @guest @fixture["csrf_guest"]["decoded"]["session"]
  @secret "phoenix-a2-cookie-fixture-secret-not-for-production"
  @now ~U[2026-10-01 16:00:00Z]

  test "management protocol retains Warden identity and Rails OTP consumption projections" do
    alias Dawarich.Auth.TwoFactor.{BackupCodes, Totp}
    corpus = File.read!("test/fixtures/auth/two_factor/requests.json") |> Jason.decode!()
    otp = File.read!("test/fixtures/auth/two_factor/otp.json") |> Jason.decode!()
    user = @fixture["login"]["user"]

    before =
      Map.merge(@guest, %{
        "user_return_to" => "/stats",
        "locale" => "en",
        "a11c" => "retain",
        "devise.test" => "retain",
        "warden.user.user.key" => [[user["id"]], binary_part(user["encrypted_password"], 0, 29)]
      })

    for row <- corpus, row["session_retained"] do
      {session, cookie} = SessionCookie.for_form(before, @secret)
      assert RailsCookies.decrypt(cookie, "_dawarich_session", @secret, @now) == {:ok, session}

      for {key, retained} <- row["session_retained"] do
        assert session[key] == before[key] == retained, row["name"] <> ":" <> key
      end

      assert session == before
      assert session["warden.user.user.key"] == before["warden.user.user.key"]
    end

    secret = Totp.generate_secret(Base.decode16!(otp["entropy_hex"], case: :lower))

    for vector <- otp["vectors"] do
      expected = if vector["valid"], do: {:ok, vector["result_timestep"]}, else: :invalid
      assert Totp.verify(secret, vector["code"], vector["at"], vector["consumed"]) == expected
    end

    {:ok, remaining} = BackupCodes.consume([user["encrypted_password"]], "safepassword12")
    assert remaining == []
    assert BackupCodes.consume(remaining, "safepassword12") == :invalid
  end

  test "account bypass rewrites the Warden salt with source session retention" do
    Code.ensure_loaded!(SessionCookie)
    assert function_exported?(SessionCookie, :for_account_update, 4)
    source = "test/fixtures/auth/account/requests.json" |> File.read!() |> Jason.decode!()
    oracle = Enum.find(source, &(&1["name"] == "both"))["session"]
    user = Map.take(@fixture["login"]["user"], ["id", "encrypted_password"])
    user = %{id: user["id"], encrypted_password: user["encrypted_password"]}

    before =
      Map.merge(@guest, %{
        "locale" => "en",
        "user_return_to" => "/stats",
        "a11rest" => "retain",
        "warden.user.user.key" => [[user.id], "old"],
        "warden.user.user.session" => %{"last_request_at" => 42},
        "devise.test" => "expire",
        "devise.oauth_data" => "expire",
        "flash" => %{"discard" => ["notice"], "flashes" => %{"notice" => "old"}}
      })

    notice = "Your account has been updated successfully."
    {updated, cookie} = SessionCookie.for_account_update(before, user, notice, @secret)
    {:ok, decoded} = RailsCookies.decrypt(cookie, "_dawarich_session", @secret, @now)
    compatible = decoded == updated
    assert compatible

    for {key, retained} <- oracle["retained"] do
      actual = updated[key] == before[key]
      assert actual == retained, key
    end

    warden_retained = updated["warden.user.user.key"] == before["warden.user.user.key"]
    assert warden_retained == oracle["warden_salt_retained"]

    salt_matches =
      updated["warden.user.user.key"] == [[user.id], binary_part(user.encrypted_password, 0, 29)]

    assert salt_matches == oracle["warden_matches_actor"]
    assert updated["warden.user.user.session"] == before["warden.user.user.session"]
    refute Map.has_key?(updated, "devise.test")
    refute Map.has_key?(updated, "devise.oauth_data")
    assert updated["flash"]["flashes"] == oracle["flash"]
    assert updated["flash"]["discard"] == []

    assert_raise DawarichWeb.RailsSession.Overflow, fn ->
      SessionCookie.for_account_update(
        Map.put(before, "a11rest", String.duplicate("x", 5_000)),
        user,
        notice,
        @secret
      )
    end
  end

  test "accepts actual Rails global and per-form tokens with action binding" do
    form = rails_token(@fixture["csrf_guest"]["form_token"])
    meta = rails_token(@fixture["csrf_guest"]["meta_token"])
    assert ActionCsrf.valid?(@guest, form, "POST", "/users/sign_in")
    assert ActionCsrf.valid?(@guest, meta, "POST", "/users/sign_in")
    refute ActionCsrf.valid?(@guest, form, "DELETE", "/users/sign_out")
    refute ActionCsrf.valid?(@guest, "invalid", "POST", "/users/sign_in")
  end

  test "login rotates the session, clears the old CSRF and emits legacy Warden credentials" do
    user = %{
      id: @fixture["login"]["user"]["id"],
      encrypted_password: @fixture["login"]["user"]["encrypted_password"]
    }

    before = Map.put(@guest, "user_return_to", "/stats")

    {after_login, cookie} =
      SessionCookie.for_login(before, user, "Signed in successfully.", @secret)

    assert {:ok, ^after_login} = RailsCookies.decrypt(cookie, "_dawarich_session", @secret, @now)
    assert after_login["session_id"] != before["session_id"]

    assert after_login["warden.user.user.key"] == [
             [user.id],
             binary_part(user.encrypted_password, 0, 29)
           ]

    refute Map.has_key?(after_login, "_csrf_token")
    refute Map.has_key?(after_login, "user_return_to")

    refute ActionCsrf.valid?(
             after_login,
             rails_token(@fixture["csrf_guest"]["form_token"]),
             "POST",
             "/users/sign_in"
           )

    assert after_login["flash"]["flashes"]["notice"] == "Signed in successfully."

    {restored, _cookie} = SessionCookie.for_restore(%{}, user, @secret)

    assert Enum.sort(Map.keys(restored)) ==
             Enum.sort(Map.keys(@fixture["remember_restore"]["decoded"]["session"]))

    assert restored["warden.user.user.key"] == after_login["warden.user.user.key"]
  end

  test "remember restoration renews the session but keeps the CSRF token, as Devise's rememberable does" do
    user = %{
      id: @fixture["login"]["user"]["id"],
      encrypted_password: @fixture["login"]["user"]["encrypted_password"]
    }

    {restored, _cookie} = SessionCookie.for_restore(@guest, user, @secret)
    assert restored["_csrf_token"] == @guest["_csrf_token"]
    refute restored["session_id"] == @guest["session_id"]

    assert ActionCsrf.valid?(
             restored,
             rails_token(@fixture["csrf_guest"]["form_token"]),
             "POST",
             "/users/sign_in"
           )
  end

  test "logout resets the whole session and form issuance renews CSRF afterward" do
    current =
      Map.merge(@guest, %{
        "locale" => "de",
        "warden.user.user.key" => [[7], "old"],
        "devise.oauth_data" => "old"
      })

    {logged_out, cookie} = SessionCookie.for_logout("Signed out successfully.", @secret)
    assert {:ok, ^logged_out} = RailsCookies.decrypt(cookie, "_dawarich_session", @secret, @now)
    refute Map.has_key?(logged_out, "warden.user.user.key")
    refute Map.has_key?(logged_out, "locale")
    assert logged_out["session_id"] != current["session_id"]
    {form_session, _cookie} = SessionCookie.for_form(logged_out, @secret)
    assert form_session["session_id"] == logged_out["session_id"]
    refute form_session["_csrf_token"] == current["_csrf_token"]
    assert is_binary(form_session["_csrf_token"])
  end

  defp rails_token(%{"one_time_pad" => pad, "xored" => xored}),
    do:
      Base.url_encode64(Base.decode16!(pad, case: :lower) <> Base.decode16!(xored, case: :lower),
        padding: false
      )
end
