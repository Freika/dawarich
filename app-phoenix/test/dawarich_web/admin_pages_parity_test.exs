defmodule DawarichWeb.AdminPagesParityTest do
  use Dawarich.JobsCase, async: false

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Dawarich.{ActiveRecordEncryption, Repo}
  alias Dawarich.ReleaseMigrations.Effects.Support.InstanceSettingsRegistry
  alias Dawarich.Test.RailsUser

  @dir "test/fixtures/admin_pages"
  @cases ~w(photon geoapify nominatim locationiq rate_limit points invalid default pinned tls unreadable legacy health_absent health_ok health_alarm health_unknown)

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Dawarich.FixtureCleanup.delete!(Repo, ~w(instance_settings  service_settings))
    :ok
  end

  for name <- @cases do
    @name name
    @tag a10_case: String.to_atom(@name)
    test "instance #{@name} shows the same section, field, health and status content as Rails" do
      state = Jason.decode!(File.read!(Path.join(@dir, @name <> ".json")))
      user = seed_user!(state["user"])
      env = seed_fields!(state)

      if state["legacy"] do
        Repo.insert_all("service_settings", [
          %{
            id: 10001,
            user_id: user.id,
            service: 0,
            provider: "photon",
            active: true,
            config: %{},
            created_at: ~N[2026-10-03 10:00:00],
            updated_at: ~N[2026-10-03 10:00:00]
          }
        ])
      end

      section = URI.decode_query(URI.parse(state["path"]).query || "")["section"]
      scope = Dawarich.Accounts.Scope.for_user(user, "en")
      opts = [repo: Repo, env: Map.put(env, "SELF_HOSTED", "true"), health: state["health"]]
      assert {:ok, page} = Dawarich.Admin.Instance.page(scope, section, opts)

      html =
        render_component(&DawarichWeb.AdminInstance.show/1, %{
          locale: "en",
          current_user: user,
          self_hosted: true,
          two_factor: false,
          data: page.data,
          section: page.section,
          health: page.health,
          testing: MapSet.new(),
          saves: 0
        })

      rails = File.read!(Path.join(@dir, @name <> ".html"))
      Dawarich.Test.SettingsParity.dump("instance_" <> @name, rails, html)
      expected = facts(rails)
      assert Map.take(facts(html), Map.keys(expected)) == expected

      actual_dom =
        Dawarich.Test.ParityHTML.without(
          html,
          ["[data-testid=experimental-navigation]"],
          ".min-h-content"
        )

      expected_dom = Dawarich.Test.ParityHTML.normalize(rails)

      assert actual_dom == expected_dom,
             Dawarich.Test.ParityHTML.first_difference(actual_dom, expected_dom)

      assert DawarichWeb.Layouts.page_title(
               "en",
               DawarichWeb.Translate.t("en", "admin.settings.show.title", %{})
             ) == state["title"]

      refute html =~ "synthetic-a10-reader-secret"

      if @name == "default" do
        previous = System.get_env("SELF_HOSTED")
        System.put_env("SELF_HOSTED", "false")

        try do
          for name <- ~w(background_cloud background_cloud_de) do
            cloud = @dir |> Path.join(name <> ".json") |> File.read!() |> Jason.decode!()
            locale = get_in(cloud, ["user", "settings", "locale"]) || "en"
            assert cloud["status"] == 303

            assert {:error, :cloud} =
                     Dawarich.Admin.Background.page(
                       Dawarich.Accounts.Scope.for_user(user, locale)
                     )
          end
        after
          if previous,
            do: System.put_env("SELF_HOSTED", previous),
            else: System.delete_env("SELF_HOSTED")
        end
      end
    end
  end

  @background_files Path.wildcard("test/fixtures/admin_pages/background_*.json")
  for file <- @background_files,
      state = file |> File.read!() |> Jason.decode!(),
      state["status"] == 200 do
    @background_name Path.basename(file, ".json")
    @tag :d5_background
    test "#{@background_name} renders the Rails 1.16.0 background settings DOM" do
      previous = System.get_env("SELF_HOSTED")
      System.put_env("SELF_HOSTED", "true")

      on_exit(fn ->
        if previous,
          do: System.put_env("SELF_HOSTED", previous),
          else: System.delete_env("SELF_HOSTED")
      end)

      state = @dir |> Path.join(@background_name <> ".json") |> File.read!() |> Jason.decode!()
      user = seed_user!(state["user"])
      locale = DawarichWeb.Locale.resolve(nil, user, %{})

      context = %{
        locale: locale,
        current_user: user,
        current_scope: Dawarich.Accounts.Scope.for_user(user, locale),
        self_hosted: true,
        two_factor: false,
        rails_csrf_token: "CSRF"
      }

      assert {:ok, page} = DawarichWeb.SettingsLive.BackgroundJobs.page(context)
      assert page.data.visits == state["visits"]
      assert page.data.notice == state["notice"]

      html =
        render_component(
          &DawarichWeb.SettingsLive.BackgroundJobs.render/1,
          Map.merge(
            context,
            Map.merge(page, %{
              accepted_jobs: MapSet.new(),
              pending_job: nil,
              visits_pending: false,
              dialog_open: false
            })
          )
        )

      rails = File.read!(Path.join(@dir, @background_name <> ".html"))
      Dawarich.Test.SettingsParity.dump(@background_name, rails, html)

      for id <-
            ~w(native-open-start_reverse_geocoding native-open-continue_reverse_geocoding native-visits-toggle) do
        assert LazyHTML.from_fragment(html)
               |> LazyHTML.query("##{id}")
               |> LazyHTML.attribute("href") == ["#"]
      end

      targets = %{
        "native-open-start_reverse_geocoding" =>
          "/settings/background_jobs?job_name=start_reverse_geocoding",
        "native-open-continue_reverse_geocoding" =>
          "/settings/background_jobs?job_name=continue_reverse_geocoding",
        "native-visits-toggle" =>
          "/settings/background_jobs?" <>
            URI.encode_query(%{
              "settings[visits_suggestions_enabled]" =>
                if(page.data.visits, do: "false", else: "true")
            })
      }

      html =
        Regex.replace(~r/<a\b[^>]*>/, html, fn tag ->
          case Regex.run(~r/\bid="([^"]+)"/, tag, capture: :all_but_first) do
            [id] when is_map_key(targets, id) ->
              String.replace(tag, "href=\"#\"", "href=\"#{targets[id]}\"")

            _ ->
              tag
          end
        end)

      rails =
        Enum.reduce(
          [
            {"alert m-5", "alert w-auto m-5"},
            {"alert alert-info m-5", "alert alert-info w-auto m-5"},
            {"card bg-base-300 w-96 shadow-xl m-5",
             "card bg-base-300 w-full sm:w-96 shadow-xl my-5 sm:m-5"}
          ],
          rails,
          fn {from, to}, html -> String.replace(html, "class=\"#{from}\"", "class=\"#{to}\"") end
        )

      actual =
        Dawarich.Test.ParityHTML.without(
          html,
          ["#background-job-confirm", "#background-visits-confirm", "#phoenix-jobs"],
          ".min-h-content"
        )

      expected = Dawarich.Test.ParityHTML.normalize(rails)
      assert actual == expected, Dawarich.Test.ParityHTML.first_difference(actual, expected)
    end
  end

  defp seed_user!(row) do
    RailsUser.insert!(%{
      id: row["id"],
      email: row["email"],
      admin: row["admin"],
      theme: row["theme"],
      settings: row["settings"],
      status: row["status"],
      plan: row["plan"],
      changelog_consent: row["changelog_consent"]
    })

    Dawarich.Accounts.get(row["id"])
  end

  defp seed_fields!(state) do
    {:ok, key} = ActiveRecordEncryption.key(%{})

    for {name, var, kind, _} <- InstanceSettingsRegistry.definitions(),
        field = state["fields"][name],
        reduce: state["env"] do
      env ->
        cond do
          field["unreadable"] ->
            Repo.insert_all("instance_settings", [
              %{
                key: name,
                encrypted_value: "synthetic-corrupt",
                created_at: ~N[2026-10-03 10:00:00],
                updated_at: ~N[2026-10-03 10:00:00]
              }
            ])

            env

          field["source"] == "stored" ->
            row =
              if kind == :secret do
                %{
                  encrypted_value:
                    ActiveRecordEncryption.encrypt("synthetic-a10-reader-secret", key)
                }
              else
                %{value: field["value"]}
              end

            Repo.insert_all("instance_settings", [
              Map.merge(row, %{
                key: name,
                created_at: ~N[2026-10-03 10:00:00],
                updated_at: ~N[2026-10-03 10:00:00]
              })
            ])

            env

          kind == :secret and field["source"] == "env" ->
            Map.put(env, var, "synthetic-a10-reader-secret")

          true ->
            env
        end
    end
  end

  defp facts(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("[data-testid]")
    |> Enum.reject(&(LazyHTML.attribute(&1, "data-testid") == ["experimental-navigation"]))
    |> Map.new(fn node ->
      {hd(LazyHTML.attribute(node, "data-testid")),
       {node |> LazyHTML.text() |> String.split() |> Enum.join(" "),
        LazyHTML.attribute(node, "data-status")}}
    end)
  end
end
