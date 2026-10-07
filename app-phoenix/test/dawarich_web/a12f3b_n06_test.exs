defmodule DawarichWeb.A12f3bN06Test do
  use Dawarich.DataCase, async: false
  import Plug.Conn
  alias Dawarich.{Accounts}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{OnboardingActions, RailsCsrf}

  setup do
    actor =
      RailsUser.insert!(%{
        id: 73601,
        email: "n06@test",
        settings: %{"keep" => 7},
        updated_at: ~N[2020-01-01 00:00:00]
      })

    %{actor: actor}
  end

  @tag a12f3b_case: "N06a"
  test "onboarding PATCH and PUT persist only completion once", %{actor: actor} do
    for {method, params} <- [
          {:patch, %{}},
          {:put, %{}},
          {:post, %{"_method" => "patch"}},
          {:post, %{"_method" => "put"}}
        ] do
      conn = apply(OnboardingActions, :call, [request(actor.id, method, params), :update])
      assert conn.status == 200
      assert conn.resp_body == ""
      assert Accounts.settings(actor.id) == %{"keep" => 7, "onboarding_completed" => true}
    end

    assert [[stamp]] = rows("SELECT updated_at FROM users WHERE id=$1", [actor.id])
    assert NaiveDateTime.compare(stamp, ~N[2020-01-01 00:00:00]) == :gt
    apply(OnboardingActions, :call, [request(actor.id, :patch, %{}), :update])
    assert rows("SELECT updated_at FROM users WHERE id=$1", [actor.id]) == [[stamp]]
    bad = request(actor.id, :patch, %{"authenticity_token" => "bad"})
    assert apply(OnboardingActions, :call, [bad, :update]).status == 422

    guest =
      request(actor.id, :patch, %{}) |> assign(:current_user, nil) |> assign(:rails_session, %{})

    assert apply(OnboardingActions, :call, [guest, :update]).status == 302
  end

  @tag a12f3b_case: "N06b"
  test "onboarding failure cannot close the modal as success", %{actor: actor} do
    Repo.query!(
      "CREATE FUNCTION pg_temp.n06_fail() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'onboarding save rejected'; END $$"
    )

    Repo.query!(
      "CREATE TRIGGER n06_fail BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION pg_temp.n06_fail()"
    )

    assert apply(OnboardingActions, :call, [request(actor.id, :patch, %{}), :update]).status ==
             500

    assert Accounts.settings(actor.id) == %{"keep" => 7}
  end

  defp request(id, method, params) do
    session = RailsUser.session(id)

    Plug.Test.conn(method, "/settings/onboarding")
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
