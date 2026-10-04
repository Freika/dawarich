if Enum.at(System.argv(), 1) == "api_two_factor_management" do
  unless System.get_env("PHOENIX_TEST_DATABASE") == "dawarich_phoenix_test_a4otp",
    do: raise("A4 OTP own test DB required")

  Ecto.Adapters.SQL.Sandbox.unboxed_run(Dawarich.Repo, fn ->
    Dawarich.Auth.ApiProtocol.write(hd(System.argv()), System.get_env())
  end)

  IO.puts("A4 OTP native API protocol emitted; owned actors removed")
  System.halt(0)
end

alias Dawarich.Auth.{RememberCookie, SessionCookie}
alias DawarichWeb.RailsCsrf

fixture = Jason.decode!(File.read!("test/fixtures/auth/requests.json"))
source = fixture["login"]["user"]
user = %{id: source["id"], encrypted_password: source["encrypted_password"]}
secret = Application.fetch_env!(:dawarich, :rails_secret)

if Enum.at(System.argv(), 1) == "web_otp_source" do
  alias Dawarich.Auth.Otp.{Completion, Start}
  alias Dawarich.{Repo, RailsCookies, Test.RailsUser}
  label = "web OTP protocol carries source pending and completed projections across runtimes"

  unless System.get_env("PHOENIX_TEST_DATABASE") == "dawarich_phoenix_test_a11d",
    do: raise("A11d own test DB required")

  payload = File.read!(hd(System.argv())) |> Jason.decode!()
  rails = Map.fetch!(payload, "rails")
  id = payload["user_id"]
  email = payload["email"]

  unless id == 75_603 and email == "a11d-protocol@dawarich.test",
    do: raise("A11d synthetic identity required")

  {:ok, session} =
    RailsCookies.decrypt(
      rails["cookie"],
      "_dawarich_session",
      secret,
      DateTime.from_unix!(payload["at"])
    )

  unless session == rails["session"], do: raise("#{label}: source cookie mismatch")

  unless Dawarich.Auth.ActionCsrf.valid?(
           session,
           rails["form_token"],
           "POST",
           "/users/otp_challenge"
         ),
         do: raise("#{label}: source CSRF refused")

  now = DateTime.from_unix!(payload["at"] * 1_000_000, :microsecond)

  context = %{
    self_hosted: true,
    oidc: false,
    env: payload["env"],
    clock: fn -> now end,
    ip: "127.0.0.1",
    remember: "1"
  }

  Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
    [[count]] =
      Repo.query!("SELECT count(*) FROM users WHERE id=$1 OR email=$2", [id, email], log: false).rows

    unless count == 0, do: raise("A11d synthetic actor already exists")

    RailsUser.insert!(%{
      id: id,
      email: email,
      encrypted_password: rails["hash"],
      otp_secret: rails["ciphertext"],
      otp_required_for_login: true,
      otp_backup_codes: rails["backups"],
      api_key: "synthetic source words",
      settings: %{}
    })

    try do
      {:challenge, _, _} = Start.prepare(email, "safepassword12", %{}, context)
      {:ok, prepared} = Completion.prepare(session, payload["code"], context)
      true = prepared.remember
      {:ok, _} = Completion.commit(prepared, context)
      {:handoff, _} = Completion.prepare(session, payload["code"], context)
      {:ok, prepared} = Completion.prepare(session, "a11d-source-backup", context)
      {:ok, _} = Completion.commit(prepared, context)
      {:handoff, _} = Completion.prepare(session, "a11d-source-backup", context)
    after
      Repo.query!("DELETE FROM users WHERE id=$1 AND email=$2", [id, email], log: false)
    end
  end)

  IO.puts(
    "#{label}: PASS actual Rails cookie, CSRF, ciphertext, password/backup digests, native consumption and sequential replay; actor removed"
  )

  System.halt(0)
end

if Enum.at(System.argv(), 1) == "web_otp" do
  alias Dawarich.Auth.Otp.{Completion, Pending}
  alias Dawarich.Auth.TwoFactor.{Secret, Totp}
  alias Dawarich.{Repo, Test.RailsUser}

  unless System.get_env("PHOENIX_TEST_DATABASE") == "dawarich_phoenix_test_a11d",
    do: raise("A11d own test DB required")

  path = hd(System.argv())
  if File.exists?(path), do: raise("A11d private payload already exists")
  id = 75_603
  email = "a11d-protocol@dawarich.test"
  now = ~U[2026-10-04 12:00:00.000000Z]
  otp = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
  crypto = File.read!("test/fixtures/active_record_encryption.json") |> Jason.decode!()
  env = Enum.find(crypto["environments"], &(&1["name"] == "explicit keys"))["env"]
  {:ok, ciphertext} = Secret.encrypt(otp, env)

  Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
    [[count]] =
      Repo.query!("SELECT count(*) FROM users WHERE id=$1 OR email=$2", [id, email], log: false).rows

    unless count == 0, do: raise("A11d synthetic actor already exists")

    RailsUser.insert!(%{
      id: id,
      email: email,
      encrypted_password: source["encrypted_password"],
      otp_secret: ciphertext,
      otp_required_for_login: true,
      otp_backup_codes: [source["encrypted_password"]],
      failed_otp_attempts: 3,
      api_key: "synthetic protocol words",
      settings: %{}
    })

    try do
      clock = fn ->
        tick = Process.get(:a11d_protocol_tick, 0)
        Process.put(:a11d_protocol_tick, tick + 1)
        DateTime.add(now, tick, :microsecond)
      end

      context = %{self_hosted: true, oidc: false, env: env, clock: clock, ip: "127.0.0.1"}
      pending = Pending.start(%{"locale" => "en"}, id, "1", DateTime.to_unix(now))
      {pending, pending_cookie} = SessionCookie.for_form(pending, secret)
      code = Totp.at(otp, DateTime.to_unix(now))
      {:ok, prepared} = Completion.prepare(pending, code, context)
      {:ok, totp_result} = Completion.commit(prepared, context)
      {:ok, prepared} = Completion.prepare(pending, "safepassword12", context)
      {:ok, result} = Completion.commit(prepared, context)

      {completed, completed_cookie} =
        SessionCookie.for_otp_login(
          result.session,
          result.user,
          "Signed in successfully.",
          secret
        )

      remember_cookie =
        RememberCookie.sign(
          totp_result.remember,
          secret,
          DateTime.add(now, Dawarich.Accounts.remember_for())
        )

      payload = %{
        "mode" => "web_otp",
        "user_id" => id,
        "email" => email,
        "hash" => source["encrypted_password"],
        "env" => env,
        "secret" => otp,
        "ciphertext" => ciphertext,
        "at" => DateTime.to_unix(now),
        "code" => code,
        "consumed_timestep" => result.user.consumed_timestep,
        "backups" => result.user.otp_backup_codes,
        "remember_cookie" => remember_cookie,
        "remember_created_at" => DateTime.to_iso8601(result.user.remember_created_at),
        "form_token" => RailsCsrf.masked_form_token(pending, "/users/otp_challenge", "POST"),
        "sessions" => %{
          "pending" => %{"expected" => pending, "cookie" => pending_cookie},
          "completed" => %{"expected" => completed, "cookie" => completed_cookie}
        }
      }

      {:ok, file} = File.open(path, [:write, :exclusive])

      try do
        File.chmod!(path, 0o600)
        IO.binwrite(file, Jason.encode!(payload))
      after
        File.close(file)
      end
    rescue
      error ->
        File.rm(path)
        reraise error, __STACKTRACE__
    after
      Repo.query!("DELETE FROM users WHERE id=$1 AND email=$2", [id, email], log: false)
    end
  end)

  IO.puts("A11d native web OTP protocol emitted; owned actor removed")
  System.halt(0)
end

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
