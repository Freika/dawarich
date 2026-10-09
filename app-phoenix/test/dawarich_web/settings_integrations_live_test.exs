defmodule DawarichWeb.SettingsIntegrationsLiveTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.Translate
  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    rails = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if rails,
        do: System.put_env("DAWARICH_RAILS", rails),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    env = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "true")

    on_exit(fn ->
      if env, do: System.put_env("SELF_HOSTED", env), else: System.delete_env("SELF_HOSTED")
    end)

    user =
      RailsUser.insert!(%{
        id: 8691,
        email: "native-integrations-live@dawarich.test",
        settings: %{"timezone" => "UTC"}
      })

    %{user: user, url: Dawarich.Test.NativeIntegrationStub.start!()}
  end

  defp conn_for(user), do: RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id)

  defp live_as(user, service),
    do: live(conn_for(user), "/settings/integrations?service=" <> service)

  defp escaped(key, args \\ %{}),
    do:
      Translate.t("en", key, args) |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  defp store(user, settings),
    do: Repo.query!("UPDATE users SET settings=$2 WHERE id=$1", [user.id, settings])

  test "each credential pane hides stored secrets in static and connected HTML and preserves the sentinel",
       c do
    for service <- ~w(immich photoprism airtrail teslamate) do
      secret = if service == "teslamate", do: "teslamate_password", else: service <> "_api_key"

      store(c.user, %{
        "timezone" => "UTC",
        (service <> "_url") => c.url,
        secret => "synthetic-hidden-credential",
        "teslamate_api_token" => "synthetic-hidden-token"
      })

      conn = get(conn_for(c.user), "/settings/integrations?service=" <> service)
      refute conn.resp_body =~ "synthetic-hidden"
      {:ok, view, html} = live(conn)
      refute html =~ "synthetic-hidden"
      assert has_element?(view, "input[name='settings[#{secret}]'][value='********']")

      html =
        view
        |> form("#integration-settings")
        |> render_submit(%{"settings" => %{secret => "********"}})

      assert html =~ escaped("services.settings.update.updated")
      assert Accounts.settings(c.user.id)[secret] == "synthetic-hidden-credential"
    end
  end

  test "saving every provider stores credentials and connection failure shows the Rails alert",
       c do
    for service <- ~w(immich photoprism airtrail teslamate) do
      {:ok, view, _} = live_as(c.user, service)
      secret = if service == "teslamate", do: "teslamate_password", else: service <> "_api_key"

      view
      |> form("#integration-settings")
      |> render_change(%{
        "settings" => %{(service <> "_url") => c.url, secret => "synthetic-new"}
      })

      refute server_html(view) =~ "synthetic-new"

      html =
        view
        |> form("#integration-settings")
        |> render_submit(%{
          "settings" => %{(service <> "_url") => c.url, secret => "synthetic-new"}
        })

      view |> element("[data-testid='integration-trek']") |> render_click()
      view |> element("[data-testid='integration-#{service}']") |> render_click()
      assert has_element?(view, "input[name='settings[#{secret}]'][value='********']")
      assert html =~ escaped("services.settings.update.updated")
      assert Accounts.settings(c.user.id)[secret] == "synthetic-new"
      assert Accounts.settings(c.user.id)[service <> "_connection_status"] == "ok"
    end

    {:ok, view, _} = live_as(c.user, "immich")

    html =
      view
      |> form("#integration-settings")
      |> render_submit(%{"settings" => %{"immich_url" => c.url <> "/fail"}})

    assert html =~
             escaped("services.immich.connection_tester.immich_connection_failed_code", %{
               code: 401
             })
  end

  for {service, secret} <- [
        {"immich", "immich_api_key"},
        {"photoprism", "photoprism_api_key"},
        {"airtrail", "airtrail_api_key"},
        {"teslamate", "teslamate_password"},
        {"teslamate", "teslamate_api_token"}
      ] do
    test "#{secret} changes never echo typed secrets and submission persists them", c do
      service = unquote(service)
      secret = unquote(secret)

      for stored <- [nil, "synthetic-stored"] do
        store(c.user, %{"timezone" => "UTC", secret => stored})
        {:ok, view, _} = live_as(c.user, service)
        params = %{"settings" => %{(service <> "_url") => c.url, secret => "synthetic-typed"}}
        view |> form("#integration-settings") |> render_change(params)
        refute server_html(view) =~ "synthetic-typed"
        assert has_element?(view, "#settings_#{secret}[phx-update='ignore']")
        refute Accounts.settings(c.user.id)[secret] == "synthetic-typed"
        view |> form("#integration-settings") |> render_submit(params)
        assert Process.alive?(view.pid)
        assert Accounts.settings(c.user.id)[secret] == "synthetic-typed"
      end
    end
  end

  test "secret fields keep the Rails placeholder and password-manager hints", c do
    {:ok, view, _} = live_as(c.user, "immich")
    assert has_element?(view, "#settings_immich_api_key[placeholder]")
    {:ok, view, _} = live_as(c.user, "teslamate")
    assert has_element?(view, "#settings_teslamate_password[autocomplete='current-password']")
    assert has_element?(view, "#settings_teslamate_username[autocomplete='username']")
  end

  defp server_html(view),
    do: rendered_to_string(view.module.render(:sys.get_state(view.pid).socket.assigns))

  test "Phoenix filters nested integration credentials while retaining ordinary fields" do
    params = %{
      "settings" =>
        Map.new(
          ~w(password immich_api_key airtrail_api_key teslamate_password teslamate_api_token token secret),
          &{&1, "synthetic-filtered"}
        )
    }

    params = put_in(params, ["settings", "immich_url"], "https://example.test")
    filtered = Phoenix.Logger.filter_values(params)

    for key <-
          ~w(password immich_api_key airtrail_api_key teslamate_password teslamate_api_token token secret),
        do: assert(filtered["settings"][key] == "[FILTERED]")

    assert filtered["settings"]["immich_url"] == "https://example.test"
  end

  test "pane patches survive reload and SSL changes are local until save without photo import buttons",
       c do
    {:ok, view, _} = live_as(c.user, "unknown")
    assert has_element?(view, "[data-testid='integration-immich'][aria-current='page']")
    view |> element("[data-testid='integration-airtrail']") |> render_click()
    assert_patch(view, "/settings/integrations?service=airtrail")
    assert has_element?(view, "#settings_airtrail_url")

    view
    |> form("#integration-settings")
    |> render_change(%{"settings" => %{"airtrail_skip_ssl_verification" => "true"}})

    assert has_element?(view, "#airtrail-ssl-warning:not(.hidden)")
    refute Accounts.settings(c.user.id)["airtrail_skip_ssl_verification"]
    refute render(view) =~ "onchange="
    refute render(view) =~ "start_immich_import"
    refute render(view) =~ "start_photoprism_import"
    {:ok, fresh, _} = live_as(c.user, "airtrail")
    assert has_element?(fresh, "[data-testid='integration-airtrail'][aria-current='page']")
  end

  test "AirTrail and TeslaMate sync show only with URLs and repeated clicks queue once on the selected pane",
       c do
    for {service, kind} <- [
          {"airtrail", "imports.airtrail_flights"},
          {"teslamate", "imports.teslamate_sync"}
        ] do
      {:ok, view, _} = live_as(c.user, service)
      refute has_element?(view, "#integration-sync")
      store(c.user, Map.put(Accounts.settings(c.user.id), service <> "_url", c.url))
      Dawarich.Jobs.Ownership.put!(Repo, "command:" <> kind, :oban)
      {:ok, view, _} = live_as(c.user, service)
      html = view |> element("#integration-sync") |> render_click()
      assert html =~ escaped("controllers.settings.background_jobs.job_was_successfully_created")
      render_hook(view, "sync", %{})

      assert Repo.query!(
               "SELECT count(*) FROM job_outbox WHERE command_type=$1 AND aggregate_id=$2",
               [kind, c.user.id]
             ).rows == [[1]]

      assert has_element?(view, "[data-testid='integration-#{service}'][aria-current='page']")
      assert has_element?(view, "#integration-sync[disabled]")
    end
  end

  test "Lite shows the upgrade card and event-time expiry refuses saving", c do
    jwt = System.get_env("JWT_SECRET_KEY")
    System.put_env("JWT_SECRET_KEY", "synthetic-native-jwt")

    on_exit(fn ->
      if jwt, do: System.put_env("JWT_SECRET_KEY", jwt), else: System.delete_env("JWT_SECRET_KEY")
    end)

    previous = System.get_env("SELF_HOSTED")

    on_exit(fn ->
      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")
    end)

    System.put_env("SELF_HOSTED", "false")
    Repo.query!("UPDATE users SET plan=0 WHERE id=$1", [c.user.id])
    {:ok, view, html} = live_as(c.user, "immich")
    assert html =~ escaped("settings.integrations.index.upgrade_to_pro")
    refute has_element?(view, "#integration-settings")
    System.put_env("SELF_HOSTED", "true")
    {:ok, view, _} = live_as(c.user, "immich")
    Repo.query!("UPDATE users SET active_until=now()-interval '1 day' WHERE id=$1", [c.user.id])

    view
    |> form("#integration-settings")
    |> render_submit(%{"settings" => %{"immich_api_key" => "blocked"}})

    assert_redirect(view, "/")
    refute Accounts.settings(c.user.id)["immich_api_key"] == "blocked"
  end

  for service <- ~w(immich photoprism trek) do
    test "pushed sync on #{service} refuses without writing", c do
      {:ok, view, _} = live_as(c.user, unquote(service))
      settings = Accounts.settings(c.user.id)
      before = Repo.query!("SELECT count(*) FROM job_outbox").rows
      render_hook(view, "sync", %{"service" => "airtrail"})
      assert Process.alive?(view.pid)
      assert Accounts.settings(c.user.id) == settings
      assert Repo.query!("SELECT count(*) FROM job_outbox").rows == before
    end
  end

  for event <- ~w(save sync) do
    test "pushed #{event} on the Pro-required page refuses without writing", c do
      previous = Map.new(~w(SELF_HOSTED JWT_SECRET_KEY), &{&1, System.get_env(&1)})
      System.put_env("SELF_HOSTED", "false")
      System.put_env("JWT_SECRET_KEY", "synthetic-native-jwt")

      on_exit(fn ->
        for {key, value} <- previous,
            do: if(value, do: System.put_env(key, value), else: System.delete_env(key))
      end)

      Repo.query!("UPDATE users SET plan=0 WHERE id=$1", [c.user.id])
      {:ok, view, _} = live_as(c.user, "airtrail")
      settings = Accounts.settings(c.user.id)
      before = Repo.query!("SELECT count(*) FROM job_outbox").rows

      html =
        render_hook(view, unquote(event), %{
          "settings" => %{"airtrail_api_key" => "synthetic-refused"}
        })

      assert html =~ escaped("controllers.application.this_feature_requires_a_pro_plan")
      assert Process.alive?(view.pid)
      assert Accounts.settings(c.user.id) == settings
      assert Repo.query!("SELECT count(*) FROM job_outbox").rows == before
    end
  end

  def handle_query(_event, _measurements, _meta, pid), do: send(pid, :query)

  defp queries(fun) do
    id = "integrations-budget-#{System.unique_integer([:positive])}"
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

  test "integrations stays within its static and connected query budget", %{user: user} do
    {conn, static} = queries(fn -> get(conn_for(user), "/settings/integrations") end)
    {_, connected} = queries(fn -> {:ok, _, _} = live(conn) end)
    assert static <= 6
    assert connected <= 5
  end
end
