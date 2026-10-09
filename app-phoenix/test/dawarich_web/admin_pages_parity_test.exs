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
      expected = facts(rails)
      assert Map.take(facts(html), Map.keys(expected)) == expected

      assert DawarichWeb.Layouts.page_title(
               "en",
               DawarichWeb.Translate.t("en", "admin.settings.show.title", %{})
             ) == state["title"]

      refute html =~ "synthetic-a10-reader-secret"
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
