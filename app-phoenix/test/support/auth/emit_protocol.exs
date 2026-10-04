alias Dawarich.Auth.{RememberCookie, SessionCookie}
alias DawarichWeb.RailsCsrf

fixture = Jason.decode!(File.read!("test/fixtures/auth/requests.json"))
source = fixture["login"]["user"]
user = %{id: source["id"], encrypted_password: source["encrypted_password"]}
secret = Application.fetch_env!(:dawarich, :rails_secret)

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
