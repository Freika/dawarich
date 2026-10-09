defmodule DawarichWeb.StandaloneTransactionFlowTest do
  use ExUnit.Case, async: false
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.{RailsFormRequests, RailsUser}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo, sandbox: false)
    previous = Map.new(~w(DAWARICH_RAILS SELF_HOSTED FORCE_SSL), &{&1, System.get_env(&1)})
    System.put_env("DAWARICH_RAILS", "off")
    System.put_env("SELF_HOSTED", "true")
    System.put_env("FORCE_SSL", "false")

    actor =
      RailsUser.insert!(%{
        id: System.unique_integer([:positive]),
        email: "transaction-#{Ecto.UUID.generate()}@example.invalid",
        provider: "openid_connect",
        settings: %{"timezone" => "UTC", "locale" => "en", "keep" => 7}
      })

    on_exit(fn ->
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo, sandbox: false)
      user = Accounts.get(actor.id)
      if user, do: Dawarich.DemoData.Destroyer.call(Repo, user)

      for table <- ~w(points stats imports),
          do: Repo.query!("DELETE FROM #{table} WHERE user_id=$1", [actor.id], log: false)

      Repo.query!("DELETE FROM job_outbox WHERE payload->>'user_id'=$1", [to_string(actor.id)],
        log: false
      )

      Repo.query!(
        "DELETE FROM oban.oban_jobs WHERE args->>'user_id'=$1 OR args->'payload'->>'user_id'=$1 OR EXISTS(SELECT 1 FROM jsonb_array_elements_text(COALESCE(args->'payload'->'keys','[]'::jsonb)) key WHERE key LIKE 'timeline_month_summary/' || $1 || '/%')",
        [to_string(actor.id)],
        log: false
      )

      Repo.query!("DELETE FROM users WHERE id=$1", [actor.id], log: false)

      for {name, value} <- previous do
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end
    end)

    %{actor: actor, session: RailsUser.session(actor.id, %{"locale" => "en"})}
  end

  @tag :standalone_onboarding
  test "idle connection onboarding commits through the Endpoint and remains idempotent", c do
    refute Repo.in_transaction?()
    assert form(c, "/settings/onboarding", %{"_method" => "patch"}).status == 200
    assert Accounts.settings(c.actor.id)["onboarding_completed"] == true
    assert Accounts.settings(c.actor.id)["keep"] == 7

    before =
      Repo.query!("SELECT updated_at FROM users WHERE id=$1", [c.actor.id], log: false).rows

    assert form(c, "/settings/onboarding", %{"_method" => "put"}).status == 200

    assert Repo.query!("SELECT updated_at FROM users WHERE id=$1", [c.actor.id], log: false).rows ==
             before
  end

  @tag :standalone_demo_import
  test "idle connection demo import commits through the Endpoint", c do
    refute Repo.in_transaction?()
    conn = form(c, "/settings/onboarding/demo_data", %{})
    assert conn.status == 302
    assert RailsFormRequests.rails_session(conn)["flash"]["flashes"]["notice"]

    assert Repo.query!(
             "SELECT count(*) FROM imports WHERE user_id=$1 AND demo=true",
             [c.actor.id],
             log: false
           ).rows == [[1]]

    assert [[count]] =
             Repo.query!("SELECT count(*) FROM points WHERE user_id=$1", [c.actor.id], log: false).rows

    assert count > 0
  end

  @tag :standalone_demo_destroy
  test "idle connection demo removal commits through the Endpoint", c do
    Repo.query!(
      "INSERT INTO imports(user_id,name,source,status,demo,created_at,updated_at) VALUES($1,'Synthetic',6,2,true,now(),now())",
      [c.actor.id],
      log: false
    )

    refute Repo.in_transaction?()
    conn = form(c, "/settings/onboarding/demo_data", %{"_method" => "delete"})
    assert conn.status == 302
    assert RailsFormRequests.rails_session(conn)["flash"]["flashes"]["notice"]

    assert Repo.query!("SELECT count(*) FROM imports WHERE user_id=$1", [c.actor.id], log: false).rows ==
             [[0]]
  end

  @tag :standalone_account
  test "idle connection account update commits through the Endpoint", c do
    refute Repo.in_transaction?()
    conn = form(c, "/users", %{"_method" => "patch", "user[first_name]" => "Synthetic"})
    assert conn.status == 303

    assert Repo.query!("SELECT first_name FROM users WHERE id=$1", [c.actor.id], log: false).rows ==
             [["Synthetic"]]
  end

  @tag :standalone_locale
  @tag :recoverable_onboarding
  test "onboarding SQL failure rolls back inner work and preserves the outer commit", c do
    recoverable_failure(
      c,
      "users",
      "UPDATE OF settings",
      "NEW.id",
      "/settings/onboarding",
      %{"_method" => "patch"},
      500
    )
  end

  @tag :recoverable_demo_import
  test "demo import SQL failure rolls back inner work and preserves the outer commit", c do
    recoverable_failure(
      c,
      "points",
      "INSERT",
      "NEW.user_id",
      "/settings/onboarding/demo_data",
      %{},
      302
    )
  end

  @tag :recoverable_demo_destroy
  test "demo removal SQL failure restores earlier deletes and preserves the outer commit", c do
    [[import]] =
      Repo.query!(
        "INSERT INTO imports(user_id,name,source,status,demo,created_at,updated_at) VALUES($1,'Synthetic',6,2,true,now(),now()) RETURNING id",
        [c.actor.id],
        log: false
      ).rows

    Repo.query!(
      "INSERT INTO points(user_id,import_id,timestamp,lonlat,created_at,updated_at) VALUES($1,$2,1,ST_GeomFromText('POINT(0 0)',4326),now(),now())",
      [c.actor.id, import],
      log: false
    )

    recoverable_failure(
      c,
      "imports",
      "DELETE",
      "OLD.user_id",
      "/settings/onboarding/demo_data",
      %{"_method" => "delete"},
      302
    )
  end

  defp recoverable_failure(c, table, operation, owner, path, params, status) do
    name = "inner_failure_#{c.actor.id}"

    Repo.query!(
      "CREATE FUNCTION public.#{name}() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'deterministic inner failure'; END $$",
      [],
      log: false
    )

    Repo.query!(
      "CREATE TRIGGER #{name} BEFORE #{operation} ON #{table} FOR EACH ROW WHEN (#{owner}=#{c.actor.id}) EXECUTE FUNCTION public.#{name}()",
      [],
      log: false
    )

    before = snapshot(c.actor.id)

    try do
      refute Repo.in_transaction?()
      assert_failure(form(c, path, params), status)
      assert snapshot(c.actor.id) == before
      assert Repo.query!("SELECT 1", [], log: false).rows == [[1]]
      refute Repo.in_transaction?()

      assert {:ok, :handled} =
               Repo.transaction(fn ->
                 Repo.query!(
                   "UPDATE users SET first_name='Outer committed' WHERE id=$1",
                   [c.actor.id],
                   log: false
                 )

                 assert_failure(form(c, path, params), status)
                 assert snapshot(c.actor.id) == before
                 assert Repo.query!("SELECT 1", [], log: false).rows == [[1]]
                 :handled
               end)

      assert Repo.query!("SELECT first_name FROM users WHERE id=$1", [c.actor.id], log: false).rows ==
               [["Outer committed"]]

      assert snapshot(c.actor.id) == before
    after
      Repo.query!("DROP TRIGGER IF EXISTS #{name} ON #{table}", [], log: false)
      Repo.query!("DROP FUNCTION IF EXISTS public.#{name}()", [], log: false)
    end
  end

  defp snapshot(id) do
    Repo.query!(
      "SELECT settings,(SELECT count(*) FROM imports WHERE user_id=$1),(SELECT count(*) FROM points WHERE user_id=$1) FROM users WHERE id=$1",
      [id],
      log: false
    ).rows
  end

  defp assert_failure(conn, status) do
    assert conn.status == status

    if status == 302 do
      flashes = RailsFormRequests.rails_session(conn)["flash"]["flashes"]
      assert flashes["alert"]
      refute flashes["notice"]
    end
  end

  defp form(c, path, params) do
    params = Map.put(params, "authenticity_token", DawarichWeb.RailsCsrf.masked_token(c.session))

    RailsFormRequests.post_form(
      c.session,
      URI.encode_query(params),
      [{"accept", "text/html"}],
      path
    )
  end
end
