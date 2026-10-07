defmodule DawarichWeb.A12f3bN05Test do
  use Dawarich.DataCase, async: false
  import Plug.Conn
  alias Dawarich.{Accounts}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{RailsCsrf, SettingsMiscActions}

  setup do
    actor =
      RailsUser.insert!(%{
        id: 73501,
        email: "n05@test",
        api_key: "n05-old",
        settings: %{"keep" => true}
      })

    other = RailsUser.insert!(%{id: 73502, email: "n05-other@test", api_key: "n05-foreign"})
    %{actor: actor, other: other}
  end

  @tag a12f3b_case: "N05a"
  test "theme changelog and API key routes preserve response and session writes", %{
    actor: actor,
    other: other
  } do
    theme = request(actor.id, :get, "/settings/theme", %{"theme" => "light"})
    assert apply(SettingsMiscActions, :call, [theme, :theme]).status == 302
    assert Accounts.get(actor.id).theme == "light"
    consent = request(actor.id, :patch, "/settings/changelog_consent", %{"decision" => "granted"})
    assert apply(SettingsMiscActions, :call, [consent, :changelog_consent]).status == 302
    assert Accounts.get(actor.id).changelog_consent == 1
    turbo = consent |> put_req_header("accept", "text/vnd.turbo-stream.html")
    result = apply(SettingsMiscActions, :call, [turbo, :changelog_consent])
    assert result.status == 200
    assert result.resp_body =~ "version-indicator"
    assert result.resp_body =~ "changelog-consent-setting"

    Repo.query!(
      "UPDATE users SET provider='openid_connect', uid='n05-provider', otp_required_for_login=true WHERE id=$1",
      [actor.id]
    )

    conn = request(actor.id, :post, "/settings/generate_api_key", %{"user_id" => "#{other.id}"})
    assert apply(SettingsMiscActions, :call, [conn, :generate_api_key]).status == 302
    assert Accounts.by_api_key("n05-old") == nil
    assert [[key]] = rows("SELECT api_key FROM users WHERE id=$1", [actor.id])
    assert byte_size(key) == 64
    assert Accounts.by_api_key(key).id == actor.id
    assert Accounts.by_api_key("n05-foreign").id == other.id
    assert Accounts.settings(actor.id) == %{"keep" => true}
  end

  @tag a12f3b_case: "N05b"
  test "settings miscellaneous refusal occurs before session or key mutation", %{actor: actor} do
    conn = request(actor.id, :post, "/settings/theme", %{"theme" => "light"})
    assert apply(SettingsMiscActions, :call, [conn, :theme]).status == 404
    assert Accounts.get(actor.id).theme == "dark"

    for {action, path, params} <- [
          {:changelog_consent, "/settings/changelog_consent", %{"decision" => "bad"}},
          {:generate_api_key, "/settings/generate_api_key", %{"authenticity_token" => "bad"}}
        ] do
      method = if action == :changelog_consent, do: :patch, else: :post

      assert apply(SettingsMiscActions, :call, [request(actor.id, method, path, params), action]).status ==
               422
    end

    assert Accounts.by_api_key("n05-old").id == actor.id
    assert Accounts.get(actor.id).changelog_consent == nil
  end

  defp request(id, method, path, params) do
    session = RailsUser.session(id)

    Plug.Test.conn(method, path)
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> assign(
      :api_params,
      Map.merge(%{"authenticity_token" => RailsCsrf.masked_token(session)}, params)
    )
    |> assign(:api_query, %{})
    |> assign(:rails_session, session)
    |> assign(:current_user, Accounts.get(id))
  end
end
