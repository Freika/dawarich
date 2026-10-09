defmodule DawarichWeb.SettingsLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Dawarich.Test.FormIsolation

  alias Dawarich.Test.RailsUser

  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})

    user =
      RailsUser.insert!(%{
        id: 5390,
        email: "a5s3-live@dawarich.test",
        settings: %{"timezone" => "Europe/Berlin", "maps" => %{"distance_unit" => "km"}},
        api_key: "a5s3-k-5390"
      })

    %{user: user}
  end

  defp live_as(user, path, opts \\ []),
    do: live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), path, opts)

  describe "routes" do
    test "each page mounts for a signed-in user with Rails' title", %{user: user} do
      for {path, title} <- [
            {"/settings/general", "General settings | Dawarich"},
            {"/settings/integrations", "Settings | Dawarich"},
            {"/users/edit", "Account | Dawarich"},
            {"/insights", "Insights | Dawarich"}
          ] do
        {:ok, _view, html} = live_as(user, path, on_error: [duplicate_id: :warn])
        assert html =~ ">#{title}</title>", path
      end
    end

    test "the language order is Rails' I18n.available_locales" do
      assert DawarichWeb.Locale.locales() == ~w(en de es fr pl ca zh)
    end
  end

  describe "/settings/general" do
    setup %{user: user} do
      previous = System.get_env("SMTP_SERVER")
      System.put_env("SMTP_SERVER", "smtp.a5s3.test")

      :persistent_term.put(Dawarich.TimeZoneOptions, [
        {"(GMT+01:00) Europe/Berlin", "Europe/Berlin"},
        {"(GMT+09:00) Asia/Tokyo", "Asia/Tokyo"}
      ])

      on_exit(fn ->
        if previous,
          do: System.put_env("SMTP_SERVER", previous),
          else: System.delete_env("SMTP_SERVER")

        :persistent_term.erase(Dawarich.TimeZoneOptions)
      end)

      %{user: user}
    end

    test "languages in Rails' order with the page's locale checked; the user's zone selected", %{
      user: user
    } do
      Dawarich.Repo.query!(
        "UPDATE users SET settings = settings || '{\"timezone\": \"Asia/Tokyo\", \"locale\": \"de\"}' WHERE id = $1",
        [user.id]
      )

      {:ok, view, _html} = live_as(user, "/settings/general", on_error: [duplicate_id: :warn])

      assert view
             |> element(
               "[data-testid='language-choice']:first-child span[data-testid='language-name']"
             )
             |> render() =~ "English"

      assert has_element?(view, "input[name='locale'][value='de'][checked]")
      refute has_element?(view, "input[name='locale'][value='en'][checked]")
      assert has_element?(view, "#timezone option[value='Asia/Tokyo'][selected]")
      refute has_element?(view, "#timezone option[value='Europe/Berlin'][selected]")
    end

    test "without SMTP the notice replaces the digest toggles and the test email", %{user: user} do
      System.delete_env("SMTP_SERVER")
      {:ok, view, html} = live_as(user, "/settings/general", on_error: [duplicate_id: :warn])
      assert html =~ "https://dawarich.app/docs/self-hosting/configuration/smtp/"
      refute has_element?(view, "input[name='monthly_digest_emails_enabled']")
      refute has_element?(view, "#send-test-email")
    end

    test "the legacy digest key sets both toggles; news stays on by default", %{user: user} do
      Dawarich.Repo.query!(
        "UPDATE users SET settings = settings || '{\"digest_emails_enabled\": false}' WHERE id = $1",
        [user.id]
      )

      {:ok, view, _html} = live_as(user, "/settings/general", on_error: [duplicate_id: :warn])
      refute has_element?(view, "#monthly_digest_emails_enabled[checked]")
      refute has_element?(view, "#yearly_digest_emails_enabled[checked]")
      assert has_element?(view, "#news_emails_enabled[checked]")
    end

    test "the What's New card toggles through slice 1's handler while joined", %{user: user} do
      {:ok, view, _html} = live_as(user, "/settings/general", on_error: [duplicate_id: :warn])

      view
      |> element("#changelog-consent-setting form")
      |> render_submit(%{"decision" => "granted"})

      assert has_element?(view, "#changelog-consent-setting button", "Turn off notices")

      assert %{rows: [[1]]} =
               Dawarich.Repo.query!("SELECT changelog_consent FROM users WHERE id = $1", [user.id])
    end

    test "a verified supporter sees the thanks and the badge toggle; the email stays out of the state",
         %{user: user} do
      Dawarich.Repo.query!(
        "UPDATE users SET settings = settings || '{\"supporter_email\": \"a5s3-fan@dawarich.test\"}' WHERE id = $1",
        [user.id]
      )

      key =
        "dawarich/supporter:" <>
          Base.encode16(:crypto.hash(:sha256, "a5s3-fan@dawarich.test"), case: :lower)

      Dawarich.Jobs.repo().query!(
        "INSERT INTO phoenix.supporter_checks (cache_key, result, checked_at) VALUES ($1, $2, now())",
        [key, %{"supporter" => true, "platform" => "patreon"}]
      )

      on_exit(fn ->
        Dawarich.Jobs.repo().query!("DELETE FROM phoenix.supporter_checks WHERE cache_key = $1", [
          key
        ])
      end)

      {:ok, view, html} = live_as(user, "/settings/general", on_error: [duplicate_id: :warn])

      assert html =~ "Thank you for supporting Dawarich via Patreon!"
      assert has_element?(view, "input#show_supporter_badge[type='checkbox'][checked]")
      assert has_element?(view, "input#supporter_email[value='a5s3-fan@dawarich.test']")
      refute inspect(:sys.get_state(view.pid)) =~ "a5s3-fan@dawarich.test"
    end

    test "the supporter lookup never runs on Cloud, even with a cached yes", %{user: user} do
      Dawarich.Repo.query!(
        "UPDATE users SET settings = settings || '{\"supporter_email\": \"a5s3-fan@dawarich.test\"}' WHERE id = $1",
        [user.id]
      )

      key =
        "dawarich/supporter:" <>
          Base.encode16(:crypto.hash(:sha256, "a5s3-fan@dawarich.test"), case: :lower)

      Dawarich.Jobs.repo().query!(
        "INSERT INTO phoenix.supporter_checks (cache_key, result, checked_at) VALUES ($1, $2, now())",
        [key, %{"supporter" => true, "platform" => "patreon"}]
      )

      on_exit(fn ->
        Dawarich.Jobs.repo().query!("DELETE FROM phoenix.supporter_checks WHERE cache_key = $1", [
          key
        ])
      end)

      user = Dawarich.Accounts.get(user.id)
      context = %{locale: "en", now: DateTime.utc_now(), self_hosted: false, zones: []}
      assert DawarichWeb.SettingsLive.General.page(user, %{}, context).supporter == false
    end
  end

  describe "/settings/integrations" do
    defp configure(user, settings),
      do:
        Dawarich.Repo.query!("UPDATE users SET settings = settings || $2 WHERE id = $1", [
          user.id,
          settings
        ])

    test "Immich opens by default; statuses and the current service ride on the nav links", %{
      user: user
    } do
      configure(user, %{
        "immich_url" => "https://immich.a5s3.test",
        "immich_api_key" => "a5s3-k-imm",
        "immich_connection_status" => "ok"
      })

      {:ok, view, _html} =
        live_as(user, "/settings/integrations", on_error: [duplicate_id: :warn])

      assert has_element?(
               view,
               "a[data-testid='integration-immich'][aria-current='page'][data-status='connected']"
             )

      refute has_element?(view, "a[data-testid='integration-photoprism'][data-status]")
      assert has_element?(view, "input#settings_immich_url[value='https://immich.a5s3.test']")
      assert has_element?(view, "input[type='hidden'][name='service'][value='immich']")
    end

    test "an unknown service shows Immich; a self-hosted admin's old geocoding link goes to Instance settings",
         %{user: user} do
      {:ok, view, _html} =
        live_as(user, "/settings/integrations?service=geocoding", on_error: [duplicate_id: :warn])

      assert has_element?(view, "a[data-testid='integration-immich'][aria-current='page']")

      Dawarich.Repo.query!("UPDATE users SET admin = true WHERE id = $1", [user.id])

      assert {:error, {:redirect, %{to: "/admin/settings"}}} =
               live_as(user, "/settings/integrations?service=geocoding")
    end

    test "a Cloud Lite user gets the Pro card with an upgrade link and no panes", %{user: user} do
      refute DawarichWeb.SettingsLive.Integrations.page(user, %{}, %{
               locale: "en",
               now: DateTime.utc_now(),
               self_hosted: false,
               two_factor: false
             }).pro_required

      Dawarich.Repo.query!("UPDATE users SET plan = 0 WHERE id = $1", [user.id])
      System.put_env("JWT_SECRET_KEY", "phoenix-a5-jwt-fixture-secret-not-for-production")
      System.put_env("SELF_HOSTED", "false")
      on_exit(fn -> for key <- ~w(JWT_SECRET_KEY SELF_HOSTED), do: System.delete_env(key) end)
      lite = Dawarich.Accounts.get(user.id)

      page =
        DawarichWeb.SettingsLive.Integrations.page(lite, %{}, %{
          locale: "en",
          now: DateTime.utc_now(),
          self_hosted: false,
          two_factor: false
        })

      assert page.pro_required
      refute Map.has_key?(page, :upgrade)
      refute Map.has_key?(page, :service)

      {:ok, _view, html} =
        live_as(lite, "/settings/integrations", on_error: [duplicate_id: :warn])

      assert html =~ "/auth/dawarich?token="
      assert html =~ "utm_content=integrations"

      assert %{pro_required: false, service: "immich"} =
               DawarichWeb.SettingsLive.Integrations.page(lite, %{}, %{
                 locale: "en",
                 now: DateTime.utc_now(),
                 self_hosted: true,
                 two_factor: false
               })
    end

    test "TREK lists the user's sources in creation order with their actions", %{user: user} do
      for {id, created, status, importing} <- [
            {53_931, ~N[2026-09-22 10:00:00], 1, false},
            {53_932, ~N[2026-09-21 10:00:00], 0, false},
            {53_933, ~N[2026-09-23 10:00:00], 0, true}
          ] do
        Dawarich.Repo.insert_all("trip_sources", [
          %{
            id: id,
            user_id: user.id,
            provider: "trek",
            base_url: "https://trek-#{id}.a5s3.test",
            status: status,
            importing: importing,
            created_at: created,
            updated_at: created
          }
        ])
      end

      {:ok, view, html} =
        live_as(user, "/settings/integrations?service=trek", on_error: [duplicate_id: :warn])

      assert [_, first, second, third | _] = String.split(html, "https://trek-")
      assert first =~ "53932" and second =~ "53931" and third =~ "53933"
      assert has_element?(view, "a[href='/settings/trek_sources/53932/select_trips']")
      assert has_element?(view, "a[href='#trek-source-form']")
      refute has_element?(view, "a[href='/settings/trek_sources/53933/select_trips']")

      assert has_element?(
               view,
               "form[action='/settings/trek_sources/53931'] button[data-turbo-confirm]"
             )
    end

    test "integration secrets reach the page but not the LiveView state", %{user: user} do
      configure(user, %{
        "immich_url" => "https://immich.a5s3.test",
        "immich_api_key" => "a5s3-imk-1",
        "teslamate_url" => "https://tesla.a5s3.test",
        "teslamate_password" => "a5s3-k-secret-pw"
      })

      {:ok, view, html} = live_as(user, "/settings/integrations", on_error: [duplicate_id: :warn])
      assert html =~ ~s(value="a5s3-imk-1")
      refute inspect(:sys.get_state(view.pid)) =~ "a5s3-k-secret"
      refute inspect(:sys.get_state(view.pid)) =~ "a5s3-imk-1"

      {:ok, tesla, html} =
        live_as(user, "/settings/integrations?service=teslamate", on_error: [duplicate_id: :warn])

      assert html =~ ~s(value="a5s3-k-secret-pw")
      refute inspect(:sys.get_state(tesla.pid)) =~ "a5s3-k-secret"
    end
  end

  describe "/users/edit" do
    test "the API card shows the bare key, the app QR code and the key-bearing URLs", %{
      user: user
    } do
      {:ok, view, html} = live_as(user, "/users/edit")
      doc = LazyHTML.from_document(html)

      assert doc
             |> LazyHTML.query("code.block.break-all.text-sm")
             |> Enum.map(&LazyHTML.text/1)
             |> Enum.take(1) == ["a5s3-k-5390"]

      codes = doc |> LazyHTML.query("section code") |> Enum.map(&LazyHTML.text/1)

      assert codes == [
               "http://www.example.com/",
               "a5s3-k-5390",
               "http://www.example.com/api/v1/owntracks/points?api_key=a5s3-k-5390",
               "http://www.example.com/api/v1/overland/batches?api_key=a5s3-k-5390"
             ]

      payload = ~s({"server_url":"http://www.example.com/","api_key":"a5s3-k-5390"})

      assert doc |> LazyHTML.query("div.max-w-xs svg path") |> LazyHTML.attribute("d") ==
               [Dawarich.QrSvg.path(Dawarich.QrCode.modules(payload))]

      assert has_element?(
               view,
               "a[href='/settings/generate_api_key'][data-turbo-method='post'][data-turbo-confirm]"
             )

      refute inspect(:sys.get_state(view.pid)) =~ "a5s3-k-5390"
      refute inspect(:sys.get_state(view.pid)) =~ "<svg"
    end

    test "a password user confirms with the current password; an OAuth user with the email", %{
      user: user
    } do
      {:ok, view, html} = live_as(user, "/users/edit")
      assert html =~ "(12 characters minimum"
      assert has_element?(view, "#user_current_password")

      assert has_element?(
               view,
               "#delete_account_modal input#password[type='password'][required='required']"
             )

      Dawarich.Repo.query!(
        "UPDATE users SET provider = 'openid_connect', uid = 'a5s3-uid' WHERE id = $1",
        [user.id]
      )

      {:ok, oauth, html} = live_as(user, "/users/edit")
      assert html =~ "Openid Connect"
      refute has_element?(oauth, "#user_current_password")
      assert has_element?(oauth, "#delete_account_modal input#confirm_email[required='required']")
    end

    test "the import dialog is a Stimulus island with Rails' absolute direct-upload URL", %{
      user: user
    } do
      {:ok, view, _html} = live_as(user, "/users/edit")

      assert has_element?(
               view,
               "dialog#import_modal[phx-hook='RailsStimulus'][phx-update='ignore'] form[data-controller='upload'][data-upload-url-value='http://www.example.com/rails/active_storage/direct_uploads'][data-upload-user-trial-value='false']"
             )

      assert has_element?(view, "dialog#delete_account_modal[phx-update='ignore']")
    end

    test "Cloud cards: plan usage, subscription text by status, the trial card for trials", %{
      user: user
    } do
      System.put_env("JWT_SECRET_KEY", "phoenix-a5-jwt-fixture-secret-not-for-production")
      on_exit(fn -> System.delete_env("JWT_SECRET_KEY") end)
      now = ~U[2026-09-26 12:00:00Z]

      render = fn attrs ->
        Dawarich.Repo.query!(
          "UPDATE users SET status = $2, active_until = $3, subscription_source = $4, points_count = 1234567 WHERE id = $1",
          [user.id, attrs.status, attrs.until, attrs.source]
        )

        current = Dawarich.Accounts.get(user.id)

        context = %{
          locale: "en",
          now: now,
          self_hosted: false,
          base_url: "http://www.example.com"
        }

        page = DawarichWeb.AccountLive.Edit.page(current, %{}, context)

        render_component(
          &DawarichWeb.AccountLive.Edit.render/1,
          Map.merge(context, Map.merge(page, %{current_user: current, rails_csrf_token: "CSRF"}))
        )
      end

      active = render.(%{status: 1, until: ~N[2027-01-01 00:00:00], source: 1})
      assert active =~ "1,234,567"

      assert active =~
               "Change plan, update your payment method, or cancel your subscription on Manager."

      refute active =~ "Trial status"

      trial = render.(%{status: 2, until: ~N[2026-10-01 00:00:00], source: 0})
      assert trial =~ "Trial status"
      assert trial =~ ">Subscribe</a>"

      auto = render.(%{status: 2, until: ~N[2026-10-01 00:00:00], source: 1})
      assert auto =~ "btn btn-primary btn-sm glass"

      current = Dawarich.Accounts.get(user.id)

      refute Map.has_key?(
               DawarichWeb.AccountLive.Edit.page(current, %{}, %{
                 locale: "en",
                 now: now,
                 self_hosted: false,
                 base_url: "http://www.example.com"
               }),
               :manager
             )
    end
  end

  describe "Rails form controls" do
    @rails_control "form:not([phx-submit]) :is(input:not([type=hidden]):not([type=submit]), select, textarea)"
    @patched ":not([phx-update=ignore]):not([phx-update=ignore] *)"

    setup do
      previous = System.get_env("SMTP_SERVER")
      System.put_env("SMTP_SERVER", "smtp.a5s3.test")

      on_exit(fn ->
        if previous,
          do: System.put_env("SMTP_SERVER", previous),
          else: System.delete_env("SMTP_SERVER")
      end)
    end

    test "every control a user edits in a Rails form stays out of LiveView's patches, so input made before the join survives it",
         %{user: user} do
      for path <-
            ~w(/settings/integrations /settings/integrations?service=photoprism /settings/integrations?service=airtrail /settings/integrations?service=teslamate /settings/integrations?service=trek /users/edit) do
        {:ok, view, _html} = live_as(user, path, on_error: [duplicate_id: :warn])
        doc = view |> render() |> LazyHTML.from_fragment()
        assert_form_isolated(render(view))

        assert doc |> LazyHTML.query(@rails_control) |> Enum.count() > 1, path
        patched = doc |> LazyHTML.query(@rails_control <> @patched) |> LazyHTML.attribute("id")
        assert {path, patched} == {path, []}
      end
    end
  end
end
