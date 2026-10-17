import Plug.Conn
alias Dawarich.{RailsCookies, RailsSecret, Repo}
alias Dawarich.Auth.{Account, Registration}
alias DawarichWeb.{AuthHandler, RailsAuth, RailsCsrf}

System.fetch_env!("PHOENIX_TEST_DATABASE")
System.fetch_env!("PHOENIX_TEST_REDIS_URL")
System.put_env("SELF_HOSTED", "true")
Application.put_env(:dawarich, :allowed_hosts, [])
Application.put_env(:dawarich, :rails_secret, System.fetch_env!("NATIVE_ISSUANCE_SECRET"))
{:ok, _} = Dawarich.ScratchRepo.start_link()
:ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

request = fn method, path, session, params ->
  params = Map.put(params, "authenticity_token", RailsCsrf.masked_token(session))
  raw = URI.encode_query(params)

  Plug.Test.conn(method, "http://www.example.com" <> path, raw)
  |> put_req_header("content-type", "application/x-www-form-urlencoded")
  |> put_req_header("content-length", Integer.to_string(byte_size(raw)))
  |> put_req_header("origin", "http://www.example.com")
  |> put_req_header(
    "cookie",
    "_dawarich_session=" <>
      RailsCookies.encrypt(session, "_dawarich_session", RailsSecret.fetch())
  )
end

guest = fn -> %{"session_id" => "synthetic-issuance", "_csrf_token" => RailsCsrf.new_token()} end

session = fn response ->
  {:ok, decoded} =
    RailsCookies.decrypt(
      response.resp_cookies["_dawarich_session"].value,
      "_dawarich_session",
      RailsSecret.fetch(),
      DateTime.utc_now()
    )

  decoded
end

vector = fn name, response, id ->
  user = Repo.get!(Account, id)
  true = response.status in [302, 303]

  %{
    name: name,
    id: id,
    email: user.email,
    hash: user.encrypted_password,
    remembered_at: user.remember_created_at,
    session: response.resp_cookies["_dawarich_session"].value,
    remember: get_in(response.resp_cookies, ["remember_user_token", :value])
  }
end

try do
  email = "native-issuance-#{System.unique_integer([:positive])}@dawarich.test"
  context = %{self_hosted: true, oidc: false, registration_enabled: true, log_rounds: 4}

  attrs = %{
    "email" => email,
    "password" => "safepassword12",
    "password_confirmation" => "safepassword12"
  }

  {:ok, user} = Registration.create(attrs, context)
  opts = [enabled: true, native: true, registration_enabled: true]

  credentials =
    request.(:post, "/users/sign_in", guest.(), %{
      "user[email]" => email,
      "user[password]" => "safepassword12",
      "user[remember_me]" => "1"
    })
    |> AuthHandler.call(opts)

  vectors = [vector.("credentials", credentials, user.id)]

  restore =
    Plug.Test.conn(:get, "http://www.example.com/stats")
    |> put_req_header(
      "cookie",
      "remember_user_token=" <> credentials.resp_cookies["remember_user_token"].value
    )
    |> RailsAuth.call([])
    |> DawarichWeb.AuthRestore.call(enabled: true, native: true)

  restore = %{restore | status: 303}
  vectors = vectors ++ [vector.("remember_restore", restore, user.id)]

  new_email = "signup-" <> email

  params = %{
    "user[email]" => new_email,
    "user[password]" => "safepassword12",
    "user[password_confirmation]" => "safepassword12"
  }

  signup =
    request.(:post, "/users", guest.(), params)
    |> DawarichWeb.AuthRegistration.Http.call(enabled: true, context: context)

  signed = session.(signup)
  [[new_id], _] = signed["warden.user.user.key"]
  vectors = vectors ++ [vector.("registration", signup, new_id)]

  raw = "synthetic-issuance-reset"
  now = DateTime.utc_now()
  digest = Dawarich.Auth.Recovery.Token.digest(:reset_password_token, raw, RailsSecret.fetch())

  Repo.query!(
    "UPDATE users SET reset_password_token=$2,reset_password_sent_at=$3 WHERE id=$1",
    [user.id, digest, DateTime.to_naive(now)],
    log: false
  )

  params = %{
    "user[reset_password_token]" => raw,
    "user[password]" => "resetpassword12345",
    "user[password_confirmation]" => "resetpassword12345"
  }

  reset =
    request.(:patch, "/users/password", guest.(), params)
    |> DawarichWeb.AuthRecovery.Http.call(enabled: true, native: true, context: context)

  vectors = vectors ++ [vector.("recovery", reset, user.id)]

  account_user = Repo.get!(Account, user.id)

  account_session =
    guest.()
    |> Map.put("warden.user.user.key", [
      [user.id],
      String.slice(account_user.encrypted_password, 0, 29)
    ])

  params = %{
    "user[current_password]" => "resetpassword12345",
    "user[password]" => "changedpassword12345",
    "user[password_confirmation]" => "changedpassword12345"
  }

  account =
    request.(:patch, "/users", account_session, params)
    |> DawarichWeb.AuthAccount.Http.call(enabled: true, native: true, context: context)

  vectors = vectors ++ [vector.("account", account, user.id)]

  crypto = Jason.decode!(File.read!("test/fixtures/active_record_encryption.json"))
  env = Enum.find(crypto["environments"], &(&1["name"] == "explicit keys"))["env"]
  {:ok, encrypted} = Dawarich.Auth.TwoFactor.Secret.encrypt("JBSWY3DPEHPK3PXP", env)

  Repo.query!(
    "UPDATE users SET otp_required_for_login=true,otp_secret=$2,settings='{}' WHERE id=$1",
    [user.id, encrypted],
    log: false
  )

  otp_context = Map.put(context, :env, env)

  params = %{
    "user[email]" => email,
    "user[password]" => "changedpassword12345",
    "user[remember_me]" => "1"
  }

  pending =
    request.(:post, "/users/sign_in", guest.(), params)
    |> AuthHandler.call(opts ++ [otp_enabled: true, otp_context: otp_context])

  code = Dawarich.Auth.TwoFactor.Totp.at("JBSWY3DPEHPK3PXP", DateTime.to_unix(DateTime.utc_now()))

  otp =
    request.(:post, "/users/otp_challenge", session.(pending), %{"otp_attempt" => code})
    |> DawarichWeb.AuthOtp.Http.call(enabled: true, native: true, context: otp_context)

  vectors = vectors ++ [vector.("otp", otp, user.id)]
  IO.puts("NATIVE_AUTH_ISSUANCE=" <> Jason.encode!(vectors))
after
  Ecto.Adapters.SQL.Sandbox.checkin(Repo)
end
