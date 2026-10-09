defmodule Dawarich.SettingsTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.Accounts.Scope
  alias Dawarich.{Accounts, Repo, Settings}
  alias Dawarich.Test.FrameSeeds

  @smtp %{
    "SMTP_SERVER" => "synthetic.test",
    "SMTP_AUTHENTICATION" => "none",
    "SMTP_STARTTLS" => "false",
    "SMTP_FROM" => "Dawarich <settings@dawarich.test>",
    "TIME_ZONE" => "UTC"
  }

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    user = FrameSeeds.user!(8501)

    Repo.query!(
      "UPDATE users SET settings = settings || '{\"timezone\":\"UTC\",\"locale\":\"en\"}'::jsonb WHERE id=$1",
      [user.id]
    )

    %{scope: Scope.for_user(Accounts.get(user.id), "en")}
  end

  defp settings(scope), do: Accounts.settings(scope.user.id)
  defp db(sql, params), do: Repo.query!(sql, params).rows

  test "general settings store toggles, time zone, locale and badge as the form sends them", %{
    scope: scope
  } do
    assert {:ok, _} =
             Settings.update_general(scope, %{
               "monthly_digest_emails_enabled" => "0",
               "yearly_digest_emails_enabled" => "1",
               "news_emails_enabled" => "0",
               "timezone" => "Europe/Berlin",
               "locale" => "de",
               "show_supporter_badge" => "1"
             })

    stored = settings(scope)
    assert stored["timezone"] == "Europe/Berlin"
    assert stored["locale"] == "de"
    assert stored["news_emails_enabled"] in [false, "0", "false"]
  end

  test "an unknown locale or time zone is ignored and the save still succeeds", %{scope: scope} do
    assert {:ok, _} =
             Settings.update_general(scope, %{"locale" => "xx", "timezone" => "Mars/Olympus"})

    assert settings(scope)["locale"] == "en"
    assert settings(scope)["timezone"] == "UTC"
  end

  test "a time zone change resets existing stats for recalculation", %{scope: scope} do
    Repo.query!(
      "INSERT INTO stats(user_id,year,month,calculation_version,distance,created_at,updated_at) VALUES($1,2025,10,3,0,now(),now())",
      [scope.user.id]
    )

    assert {:ok, _} = Settings.update_general(scope, %{"timezone" => "Europe/Berlin"})

    assert db(
             "SELECT calculation_version, repair_deferred_at IS NOT NULL FROM stats WHERE user_id=$1",
             [scope.user.id]
           ) == [[0, true]]
  end

  describe "visits" do
    setup do
      ScratchRepo.insert_all("users", [
        %{
          id: 8502,
          email: "settings-visits@dawarich.test",
          encrypted_password: "synthetic",
          settings: %{"timezone" => "UTC", "visit_radius_meters" => 100},
          visits_redetected_at: nil,
          created_at: ~N[2026-10-03 09:00:00],
          updated_at: ~N[2026-10-03 09:00:00]
        }
      ])

      %{visits_scope: Scope.for_user(%{id: 8502}, "en")}
    end

    defp scratch(sql, params), do: ScratchRepo.query!(sql, params).rows

    test "visit settings store the detection values as integers", %{visits_scope: scope} do
      assert {:ok, _} =
               Settings.update_visits(scope, %{
                 "visit_radius_meters" => "150",
                 "visit_min_points" => "4",
                 "visit_min_duration_minutes" => "12"
               })

      [[stored]] = scratch("SELECT settings FROM users WHERE id=8502", [])
      assert stored["visit_radius_meters"] == 150
      assert stored["visit_min_points"] == 4
      assert stored["visit_min_duration_minutes"] == 12
    end

    test "a redetection is queued once and refused while it is cooling down", %{
      visits_scope: scope
    } do
      count = fn ->
        scratch(
          "SELECT count(*) FROM phoenix.rails_commands WHERE kind='visits.web_redetect'",
          []
        )
      end

      assert :ok = Settings.request_visit_redetection(scope)
      assert count.() == [[1]]

      ScratchRepo.query!("UPDATE users SET visits_redetected_at=now() WHERE id=8502")
      assert :cooldown = Settings.request_visit_redetection(scope)
      assert count.() == [[1]]
    end
  end

  describe "test email" do
    setup do
      start_oban(:settings_test_email)
      :ok
    end

    defp make_admin(scope) do
      Repo.query!("UPDATE users SET admin=true WHERE id=$1", [scope.user.id])
      scope
    end

    test "an admin on a self-hosted instance with SMTP queues one email", %{scope: scope} do
      scope = make_admin(scope)

      assert {:notice, notice} =
               Settings.send_test_email(scope,
                 env: @smtp,
                 self_hosted: true,
                 oban: :settings_test_email
               )

      assert notice =~ "@"
      assert Dawarich.ScratchRepo.query!("SELECT count(*) FROM oban.oban_jobs").rows == [[1]]
    end

    test "a non-admin, a cloud user and a missing SMTP server send nothing", %{scope: scope} do
      assert {:alert, _} =
               Settings.send_test_email(scope,
                 env: @smtp,
                 self_hosted: true,
                 oban: :settings_test_email
               )

      scope = make_admin(scope)

      assert {:alert, refusal} =
               Settings.send_test_email(scope,
                 env: @smtp,
                 self_hosted: false,
                 oban: :settings_test_email
               )

      assert refusal == "You are not authorized to perform this action."

      assert {:alert, _} =
               Settings.send_test_email(scope,
                 env: Map.delete(@smtp, "SMTP_SERVER"),
                 self_hosted: true,
                 oban: :settings_test_email
               )

      assert Dawarich.ScratchRepo.query!("SELECT count(*) FROM oban.oban_jobs").rows == [[0]]
    end

    test "admin rights are read at send time, not taken from the scope", %{scope: scope} do
      admin_scope = make_admin(scope)
      Repo.query!("UPDATE users SET admin=false WHERE id=$1", [scope.user.id])

      assert {:alert, _} =
               Settings.send_test_email(admin_scope,
                 env: @smtp,
                 self_hosted: true,
                 oban: :settings_test_email
               )
    end
  end

  defmodule SupporterStub do
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, _opts) do
      conn = fetch_query_params(conn)
      found = conn.query_params["github_username"] == "fan"

      body =
        if found,
          do: %{supporter: true, platform: "github_sponsors"},
          else: %{supporter: false}

      conn |> put_resp_content_type("application/json") |> send_resp(200, Jason.encode!(body))
    end
  end

  test "supporter verification reports success, not found and empty input", %{scope: scope} do
    server =
      start_supervised!(
        {Bandit, plug: SupporterStub, port: 0, ip: {127, 0, 0, 1}, startup_log: false}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    previous = Application.get_env(:dawarich, :supporter_verify_url)
    Application.put_env(:dawarich, :supporter_verify_url, "http://127.0.0.1:#{port}/verify")

    on_exit(fn ->
      if previous,
        do: Application.put_env(:dawarich, :supporter_verify_url, previous),
        else: Application.delete_env(:dawarich, :supporter_verify_url)
    end)

    assert {:ok, %{"supporter" => true, "platform" => "github_sponsors"}} =
             Settings.verify_supporter(scope, %{"supporter_github_username" => " Fan "})

    assert {:ok, %{"supporter" => false}} =
             Settings.verify_supporter(scope, %{"supporter_github_username" => "stranger"})

    assert {:error, :empty} = Settings.verify_supporter(scope, %{"supporter_email" => " "})
  end

  test "API key rotation replaces the key and refuses a session from before a password change",
       %{scope: scope} do
    [[hash, old_key]] =
      db("SELECT encrypted_password, api_key FROM users WHERE id=$1", [scope.user.id])

    salt = binary_part(hash, 0, 29)

    assert {:ok, user} = Settings.rotate_api_key(scope, salt)
    assert user.api_key != old_key
    assert db("SELECT api_key FROM users WHERE id=$1", [scope.user.id]) == [[user.api_key]]

    Repo.query!(
      "UPDATE users SET encrypted_password=$2 WHERE id=$1",
      [scope.user.id, Bcrypt.hash_pwd_salt("changed-password-1")]
    )

    assert {:error, :stale_session} = Settings.rotate_api_key(scope, salt)
    assert db("SELECT api_key FROM users WHERE id=$1", [scope.user.id]) == [[user.api_key]]
  end
end
