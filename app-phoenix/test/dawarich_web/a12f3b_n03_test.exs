defmodule DawarichWeb.A12f3bN03Test do
  use Dawarich.DataCase, async: false
  alias Dawarich.{Accounts, Jobs.Ownership, Settings}
  alias Dawarich.Accounts.Scope
  alias Dawarich.Test.RailsUser

  setup do
    actor =
      RailsUser.insert!(%{
        id: 73301,
        email: "n03@test",
        settings: %{"timezone" => "UTC", "keep" => 7, "digest_emails_enabled" => true}
      })

    Repo.query!(
      "INSERT INTO stats (user_id, year, month, calculation_version, distance, created_at, updated_at) VALUES ($1,2025,1,3,0,NOW(),NOW())",
      [actor.id]
    )

    Ownership.put!(Repo, "command:stats.calculate_month", :sidekiq)
    %{actor: actor}
  end

  @tag a12f3b_case: "N03a"
  test "general settings save preserves coercion locale timezone and email flags", %{
    actor: actor
  } do
    params = %{
      "timezone" => "Berlin",
      "locale" => "de",
      "monthly_digest_emails_enabled" => "",
      "yearly_digest_emails_enabled" => "off",
      "news_emails_enabled" => "yes",
      "ignored" => %{"nested" => "x"}
    }

    assert {:ok, _} = Settings.update_general(scope(actor), params)
    settings = Accounts.settings(actor.id)
    assert settings["timezone"] == "Berlin"
    assert settings["locale"] == "de"
    assert settings["keep"] == 7
    assert settings["monthly_digest_emails_enabled"] == nil
    assert settings["yearly_digest_emails_enabled"] == false
    assert settings["news_emails_enabled"] == true
    refute Map.has_key?(settings, "digest_emails_enabled")

    assert rows(
             "SELECT calculation_version, repair_deferred_at IS NOT NULL FROM stats WHERE user_id=$1",
             [actor.id]
           ) == [[0, true]]

    assert [["stats.calculate_month", payload]] = commands()
    assert payload["notify_on_failure"] == false

    assert {:ok, _} = Settings.update_general(scope(actor), params)

    assert length(commands()) == 1

    assert {:ok, _} =
             Settings.update_general(scope(actor), %{
               "timezone" => "invalid",
               "news_emails_enabled" => "false"
             })

    assert Accounts.settings(actor.id)["timezone"] == "Berlin"
  end

  @tag a12f3b_case: "N03b"
  test "general failed save preserves prior settings and effects", %{actor: actor} do
    Repo.query!(
      "CREATE FUNCTION pg_temp.n03_fail() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'settings save rejected'; END $$"
    )

    Repo.query!(
      "CREATE TRIGGER n03_fail BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION pg_temp.n03_fail()"
    )

    before = Accounts.settings(actor.id)

    assert {:error, :save_failed} =
             Settings.update_general(scope(actor), %{"timezone" => "Berlin"})

    assert Accounts.settings(actor.id) == before
    assert commands() == []
    assert rows("SELECT calculation_version FROM stats WHERE user_id=$1", [actor.id]) == [[3]]
  end

  defp scope(actor), do: Scope.for_user(Accounts.get(actor.id), "en")
end
