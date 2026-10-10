defmodule DawarichWeb.SettingsGeneralLiveTest do
  use Dawarich.JobsCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.Repo
  alias Dawarich.Test.{FrameSeeds, RailsUser}
  alias DawarichWeb.Translate

  @endpoint DawarichWeb.Endpoint

  defmodule SupporterStub do
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, _opts) do
      conn = fetch_query_params(conn)

      body =
        if conn.query_params["github_username"] == "fan",
          do: %{supporter: true, platform: "github"},
          else: %{supporter: false}

      conn |> put_resp_content_type("application/json") |> send_resp(200, Jason.encode!(body))
    end
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    user = FrameSeeds.user!(8521)

    Repo.query!(
      "UPDATE users SET settings = settings || '{\"timezone\":\"Europe/Berlin\",\"locale\":\"en\"}'::jsonb WHERE id=$1",
      [user.id]
    )

    env =
      Map.new(
        ~w(SELF_HOSTED SMTP_SERVER SMTP_AUTHENTICATION JWT_SECRET_KEY),
        &{&1, System.get_env(&1)}
      )

    System.put_env("SELF_HOSTED", "true")
    System.put_env("SMTP_SERVER", "smtp.settings-general.test")

    :persistent_term.put(Dawarich.TimeZoneOptions, [
      {"(GMT+01:00) Europe/Berlin", "Europe/Berlin"},
      {"(GMT+09:00) Asia/Tokyo", "Asia/Tokyo"}
    ])

    on_exit(fn ->
      for {key, value} <- env,
          do: if(value, do: System.put_env(key, value), else: System.delete_env(key))

      :persistent_term.erase(Dawarich.TimeZoneOptions)
    end)

    %{user: user}
  end

  defp conn_for(user), do: RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id)
  defp live_as(user), do: live(conn_for(user), "/settings/general")

  defp stored(user),
    do: Repo.query!("SELECT settings FROM users WHERE id=$1", [user.id]).rows |> hd() |> hd()

  defp text(locale, key, bindings \\ %{}),
    do:
      Translate.t(locale, "controllers.settings.general." <> key, bindings)
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()

  defp save(view, params),
    do:
      view
      |> form("#general-settings")
      |> render_submit(
        Map.merge(
          %{
            "monthly_digest_emails_enabled" => "true",
            "yearly_digest_emails_enabled" => "true",
            "news_emails_enabled" => "true",
            "locale" => "en",
            "timezone" => "Europe/Berlin"
          },
          params
        )
      )

  defp jobs(user),
    do:
      Repo.query!(
        "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Mail.TestEmailWorker' AND args->>'user_id'=$1",
        [to_string(user.id)]
      ).rows

  test "saving the toggles and the time zone stores them and shows the notice in place", %{
    user: user
  } do
    {:ok, view, _html} = live_as(user)

    html =
      save(view, %{
        "monthly_digest_emails_enabled" => "false",
        "news_emails_enabled" => "false",
        "timezone" => "Asia/Tokyo"
      })

    assert html =~ text("en", "settings_updated")
    settings = stored(user)
    assert settings["timezone"] == "Asia/Tokyo"
    assert Dawarich.UserSettings.cast(settings["monthly_digest_emails_enabled"]) == false
    assert Dawarich.UserSettings.cast(settings["news_emails_enabled"]) == false
    assert Dawarich.UserSettings.cast(settings["yearly_digest_emails_enabled"]) == true
    assert has_element?(view, "#general-settings select option[value='Asia/Tokyo'][selected]")
  end

  test "a save that finds no account shows the Rails alert instead of crashing", %{user: user} do
    {:ok, view, _html} = live_as(user)
    %{assigns: assigns} = :sys.get_state(view.pid).socket
    Repo.query!("UPDATE users SET deleted_at=now() WHERE id=$1", [user.id])

    socket = %Phoenix.LiveView.Socket{
      assigns: Map.take(assigns, ~w(current_scope locale flash __changed__)a)
    }

    assert {:noreply, socket} =
             DawarichWeb.SettingsLive.General.handle_event(
               "save",
               %{"timezone" => "Asia/Tokyo"},
               socket
             )

    assert socket.assigns.flash["alert"] ==
             Translate.t("en", "controllers.settings.general.failed_to_update_settings", %{})
  end

  test "a new language is saved and the page reloads in it", %{user: user} do
    {:ok, view, _html} = live_as(user)

    save(view, %{"locale" => "de"})

    flash = assert_redirect(view, "/settings/general")
    assert flash["notice"] == text("de", "settings_updated")
    assert stored(user)["locale"] == "de"

    html = conn_for(user) |> get("/settings/general") |> html_response(200)
    assert html =~ ~s(<html lang="de")
    assert html =~ Translate.t("de", "settings.general.index.general_settings", %{})
  end

  test "picking a language without saving keeps the choice on the page", %{user: user} do
    {:ok, view, _html} = live_as(user)

    view |> form("#general-settings") |> render_change(%{"locale" => "fr"})

    assert has_element?(view, "input[name='locale'][value='fr'][checked]")
    assert stored(user)["locale"] == "en"
  end

  test "only a self-hosted admin with SMTP can send a test email, and it is queued once", %{
    user: user
  } do
    {:ok, view, _html} = live_as(user)
    refute has_element?(view, "#send-test-email")
    assert render_hook(view, "send_test_email", %{}) =~ "not authorized"
    assert jobs(user) == [[0]]

    Repo.query!("UPDATE users SET admin=true WHERE id=$1", [user.id])
    {:ok, view, _html} = live_as(user)
    assert has_element?(view, "#send-test-email[type=button][phx-disable-with]")

    html = view |> element("#send-test-email") |> render_click()

    email = Repo.query!("SELECT email FROM users WHERE id=$1", [user.id]).rows |> hd() |> hd()
    assert html =~ text("en", "test_email_queued", %{"email" => email})
    assert jobs(user) == [[1]]

    System.delete_env("SMTP_SERVER")
    {:ok, view, _html} = live_as(user)
    refute has_element?(view, "#send-test-email")
  end

  test "unsupported SMTP authentication refuses test email without enqueueing", %{user: user} do
    System.put_env("SMTP_AUTHENTICATION", "unsupported")
    Repo.query!("UPDATE users SET admin=true WHERE id=$1", [user.id])
    {:ok, view, _} = live_as(user)
    assert has_element?(view, "#send-test-email")
    html = view |> element("#send-test-email") |> render_click()
    assert html =~ text("en", "smtp_not_configured")
    assert Process.alive?(view.pid)
    assert jobs(user) == [[0]]
  end

  test "on Cloud even an admin gets no test email, supporter, What's New or Background Jobs", %{
    user: user
  } do
    System.put_env("SELF_HOSTED", "false")
    System.put_env("JWT_SECRET_KEY", "settings-general-cloud-test-secret")
    Repo.query!("UPDATE users SET admin=true WHERE id=$1", [user.id])
    {:ok, view, html} = live_as(user)

    refute has_element?(view, "#send-test-email")
    refute has_element?(view, "#supporter-form")
    refute has_element?(view, "#changelog-consent-setting")
    refute html =~ "/settings/background_jobs"
    assert render_hook(view, "send_test_email", %{}) =~ "not authorized"
    assert jobs(user) == [[0]]
  end

  test "supporter verification thanks a supporter and explains a miss or an empty form", %{
    user: user
  } do
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

    {:ok, view, _html} = live_as(user)
    verify = fn params -> view |> form("#supporter-form") |> render_submit(params) end

    assert verify.(%{"supporter_email" => " "}) =~
             text("en", "please_enter_an_email_address_or_github_username")

    assert verify.(%{"supporter_github_username" => "stranger"}) =~
             text("en", "not_found_in_supporter_list_make_sure_you_re_using")

    html = verify.(%{"supporter_github_username" => "fan"})

    assert html =~
             text("en", "verified_thank_you_for_supporting_dawarich_via_platform", %{
               platform: "Github"
             })

    assert has_element?(view, "#general-settings input[name='show_supporter_badge']")
  end

  def handle_query(_event, _measurements, _meta, pid), do: send(pid, :query)

  defp queries(fun) do
    id = "general-budget-#{System.unique_integer([:positive])}"
    :telemetry.attach(id, [:dawarich, :repo, :query], &__MODULE__.handle_query/4, self())
    result = fun.()
    :telemetry.detach(id)
    {result, drain(0)}
  end

  defp drain(n) do
    receive do
      :query -> drain(n + 1)
    after
      0 -> n
    end
  end

  test "the page stays within the Rails-era query budget", %{user: user} do
    {conn, static} = queries(fn -> get(conn_for(user), "/settings/general") end)
    {_, connected} = queries(fn -> {:ok, _view, _html} = live(conn) end)

    assert static <= 4
    assert connected <= 4
  end
end
