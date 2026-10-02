alias Dawarich.Auth.{RememberCookie, SessionCookie}
alias DawarichWeb.RailsCsrf

fixture = Jason.decode!(File.read!("test/fixtures/auth/requests.json"))
source = fixture["login"]["user"]
user = %{id: source["id"], encrypted_password: source["encrypted_password"]}
secret = Application.fetch_env!(:dawarich, :rails_secret)
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
