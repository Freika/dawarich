if Enum.at(System.argv(), 1) == "api_two_factor_management" do
  alias Dawarich.Auth.Account
  alias Dawarich.Auth.TwoFactor.{Api, Totp}
  alias Dawarich.Repo

  defmodule Dawarich.ApiProtocolClearFailure do
    defdelegate one(query, opts), to: Dawarich.Repo
    defdelegate query!(sql, params, opts), to: Dawarich.Repo

    def update!(changeset, opts) do
      if Map.has_key?(changeset.changes, :otp_secret) and is_nil(changeset.changes.otp_secret),
        do: raise("A4 OTP expected clear failure"),
        else: Dawarich.Repo.update!(changeset, opts)
    end
  end

  unless System.get_env("PHOENIX_TEST_DATABASE") == "dawarich_phoenix_test_a4otp",
    do: raise("A4 OTP own test DB required")

  ids = [954_801, 954_802, 954_803]
  emails = Enum.map(ids, &"a4otp-protocol-#{&1}@example.invalid")
  now = ~U[2026-10-04 12:00:00.000000Z]
  password = "safepassword12"
  hash = Bcrypt.hash_pwd_salt(password, log_rounds: 4)
  context = %{self_hosted: true, clock: fn -> now end, backup_options: [log_rounds: 4]}

  projection = fn id ->
    actor = Repo.get!(Account, id, log: false)

    %{
      "enabled" => actor.otp_required_for_login,
      "ciphertext" => actor.otp_secret,
      "backups" => actor.otp_backup_codes,
      "consumed_timestep" => actor.consumed_timestep
    }
  end

  Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
    [[count]] =
      Repo.query!(
        "SELECT count(*) FROM users WHERE id=ANY($1) OR email=ANY($2)",
        [ids, emails],
        log: false
      ).rows

    unless count == 0, do: raise("A4 OTP synthetic actor already exists")

    rows =
      Enum.zip_with(ids, emails, fn id, email ->
        %{
          id: id,
          email: email,
          encrypted_password: hash,
          status: 1,
          plan: 1,
          settings: %{},
          api_key: "A4OTP_PROTOCOL_#{id}",
          created_at: now,
          updated_at: now
        }
      end)

    {3, _} = Repo.insert_all("users", rows, log: false)

    try do
      actors =
        Enum.map(ids, fn id ->
          params = %{"password" => password}

          {secret, current, codes} =
            if id == 954_803 do
              {:ok, 200, {:object, [{"backup_codes", codes}]}} =
                Api.run(:backup_codes, id, params, context)

              {nil, nil, codes}
            else
              {:ok, 200, {:object, setup}} = Api.run(:setup, id, params, context)
              secret = setup |> Map.new() |> Map.fetch!("secret")
              current = Totp.at(secret, DateTime.to_unix(now))

              {:ok, 200, {:object, [{"backup_codes", _}]}} =
                Api.run(:confirm, id, Map.put(params, "otp_code", current), context)

              {:ok, 200, {:object, [{"backup_codes", codes}]}} =
                Api.run(:backup_codes, id, params, context)

              {secret, current, codes}
            end

          confirmed = projection.(id)

          consumed =
            if id == 954_802 do
              try do
                Api.run(
                  :destroy,
                  id,
                  Map.put(params, "otp_code", current),
                  Map.put(context, :repo, Dawarich.ApiProtocolClearFailure)
                )

                raise "A4 OTP clear failure did not occur"
              rescue
                error in RuntimeError ->
                  unless error.message == "A4 OTP expected clear failure",
                    do: reraise(error, __STACKTRACE__)
              end

              projection.(id)
            else
              nil
            end

          {:ok, 200, _} = Api.run(:destroy, id, Map.put(params, "otp_code", hd(codes)), context)

          %{
            "id" => id,
            "email" => "a4otp-protocol-#{id}@example.invalid",
            "hash" => hash,
            "secret" => secret,
            "current_code" => current,
            "later_code" => if(secret, do: Totp.at(secret, DateTime.to_unix(now) + 30)),
            "unused_backup" => Enum.at(codes, 1),
            "confirmed" => confirmed,
            "consumed" => consumed,
            "disabled" => projection.(id)
          }
        end)

      result = %{
        "mode" => "api_two_factor_management",
        "schema" => 1,
        "summary" => "API storage only; no session issued",
        "password" => password,
        "at" => DateTime.to_unix(now),
        "actors" => actors
      }

      File.write!(hd(System.argv()), Jason.encode!(result))
      File.chmod!(hd(System.argv()), 0o600)
    after
      Repo.query!("DELETE FROM users WHERE id=ANY($1) AND email=ANY($2)", [ids, emails],
        log: false
      )
    end
  end)

  IO.puts("A4 OTP native API protocol emitted; owned actors removed")
else
  alias Dawarich.Auth.{RememberCookie, SessionCookie}
  alias DawarichWeb.RailsCsrf

  fixture = Jason.decode!(File.read!("test/fixtures/auth/requests.json"))
  source = fixture["login"]["user"]
  user = %{id: source["id"], encrypted_password: source["encrypted_password"]}
  secret = Application.fetch_env!(:dawarich, :rails_secret)

  if Enum.at(System.argv(), 1) == "two_factor_management" do
    alias Dawarich.Auth.TwoFactor.{Management, Totp}
    alias Dawarich.Repo

    unless System.get_env("PHOENIX_TEST_DATABASE") == "dawarich_phoenix_test_a11c",
      do: raise("A11c own test DB required")

    id = 74603
    email = "a11c-protocol@dawarich.test"
    now = ~U[2026-10-04 12:00:00.000000Z]
    hash = source["encrypted_password"]
    salt = binary_part(hash, 0, 29)

    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      [[count]] =
        Repo.query!("SELECT count(*) FROM users WHERE id=$1 OR email=$2", [id, email], log: false).rows

      unless count == 0, do: raise("A11c synthetic actor already exists")

      {1, _} =
        Repo.insert_all(
          "users",
          [
            %{
              id: id,
              email: email,
              encrypted_password: hash,
              status: 1,
              plan: 1,
              settings: %{},
              api_key: "A11C_PROTOCOL",
              created_at: now,
              updated_at: now
            }
          ],
          log: false
        )

      try do
        context = %{self_hosted: true, oidc: false, clock: fn -> now end}
        {:ok, %{secret: otp}} = Management.setup(id, salt, context)
        current = Totp.at(otp, DateTime.to_unix(now))
        {:ok, %{user: enabled, codes: codes}} = Management.verify(id, salt, current, context)

        {before, before_cookie} =
          SessionCookie.for_form(
            %{
              "user_return_to" => "/stats",
              "devise.test" => true,
              "warden.user.user.key" => [[id], salt]
            },
            secret
          )

        {managed, managed_cookie} = SessionCookie.for_form(before, secret)

        {:ok, %{user: disabled}} =
          Management.disable(id, salt, "safepassword12", hd(codes), context)

        projection = fn actor ->
          %{
            "enabled" => actor.otp_required_for_login,
            "ciphertext" => actor.otp_secret,
            "backups" => actor.otp_backup_codes,
            "consumed_timestep" => actor.consumed_timestep
          }
        end

        result = %{
          "mode" => "two_factor_management",
          "user_id" => id,
          "email" => email,
          "password" => "safepassword12",
          "hash" => hash,
          "secret" => otp,
          "at" => DateTime.to_unix(now),
          "current_code" => current,
          "later_code" => Totp.at(otp, DateTime.to_unix(now) + 30),
          "unused_backup" => Enum.at(codes, 1),
          "enabled" => projection.(enabled),
          "disabled" => projection.(disabled),
          "form_token" => RailsCsrf.masked_token(managed),
          "sessions" => %{
            "before" => %{"expected" => before, "cookie" => before_cookie},
            "managed" => %{"expected" => managed, "cookie" => managed_cookie}
          }
        }

        File.write!(hd(System.argv()), Jason.encode!(result))
      after
        Repo.query!("DELETE FROM users WHERE id=$1 AND email=$2", [id, email], log: false)
      end
    end)

    IO.puts("A11c native management protocol emitted; owned actor removed")
    System.halt(0)
  end

  if Enum.at(System.argv(), 1) == "account_update" do
    old_password = "a11rest-protocol-old-password"
    new_password = "a11rest-protocol-new-password"
    old_hash = Bcrypt.hash_pwd_salt(old_password, log_rounds: 4)
    new_hash = Bcrypt.hash_pwd_salt(new_password, log_rounds: 4)
    actor = %{id: 74003, encrypted_password: new_hash}

    {old, _} =
      SessionCookie.for_form(%{"user_return_to" => "/stats", "devise.test" => true}, secret)

    old = Map.put(old, "warden.user.user.key", [[actor.id], binary_part(old_hash, 0, 29)])
    old_cookie = Dawarich.RailsCookies.encrypt(old, "_dawarich_session", secret)

    {updated, updated_cookie} =
      SessionCookie.for_account_update(
        old,
        actor,
        "Your account has been updated successfully.",
        secret
      )

    result = %{
      "mode" => "account_update",
      "user_id" => actor.id,
      "old_password" => old_password,
      "new_password" => new_password,
      "new_hash" => new_hash,
      "sessions" => %{
        "old" => %{"expected" => old, "cookie" => old_cookie},
        "updated" => %{"expected" => updated, "cookie" => updated_cookie}
      }
    }

    File.write!(hd(System.argv()), Jason.encode!(result))
    System.halt(0)
  end

  {form, form_cookie} = SessionCookie.for_form(%{}, secret)
  {login, login_cookie} = SessionCookie.for_login(form, user, "Signed in successfully.", secret)
  {logout, logout_cookie} = SessionCookie.for_logout("Signed out successfully.", secret)
  now = DateTime.utc_now()

  payload = [
    [user.id],
    binary_part(user.encrypted_password, 0, 29),
    Dawarich.Accounts.remember_generated_at(now)
  ]

  result = %{
    "user_id" => user.id,
    "form_token" => RailsCsrf.masked_token(form),
    "sessions" => %{
      "form" => %{"expected" => form, "cookie" => form_cookie},
      "login" => %{"expected" => login, "cookie" => login_cookie},
      "logout" => %{"expected" => logout, "cookie" => logout_cookie}
    },
    "remember" => %{
      "expected" => payload,
      "created_at" => now |> DateTime.add(-1) |> DateTime.to_iso8601(),
      "cookie" =>
        RememberCookie.sign(payload, secret, DateTime.add(now, Dawarich.Accounts.remember_for()))
    }
  }

  File.write!(
    System.argv() |> List.first() || "../pure/native-protocol.json",
    Jason.encode!(result)
  )
end
