defmodule DawarichWeb.AdminPagesParityTest do
  use Dawarich.JobsCase, async: false

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Dawarich.{ActiveRecordEncryption, Repo}
  alias Dawarich.ReleaseMigrations.Effects.Support.InstanceSettingsRegistry
  alias Dawarich.Test.{MapStimulus, ParityHTML, RailsUser}
  alias DawarichWeb.AdminLive.Instance

  @dir "test/fixtures/admin_pages"
  @cases ~w(photon geoapify nominatim locationiq rate_limit points invalid default pinned tls unreadable legacy health_absent health_ok health_alarm health_unknown)

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Repo.query!("TRUNCATE instance_settings, service_settings", [], log: false)
    :ok
  end

  for name <- @cases do
    @name name
    @tag a10_case: String.to_atom(@name)
    test "instance #{@name} matches Rails" do
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

      params = URI.decode_query(URI.parse(state["path"]).query || "")

      context = %{
        locale: "en",
        current_user: user,
        rails_csrf_token: "CSRF",
        self_hosted: true,
        two_factor: false,
        repo: Repo,
        env: env,
        health: state["health"]
      }

      assert {:ok, page} = Instance.page(params, context)
      html = render_component(&Instance.render/1, Map.merge(context, page))
      rails = File.read!(Path.join(@dir, @name <> ".html"))
      assert ParityHTML.normalize(html) == ParityHTML.normalize(rails)

      assert MapStimulus.attributes(html, [".min-h-content"]) ==
               MapStimulus.attributes(rails, [".min-h-content"])

      assert DawarichWeb.Layouts.page_title("en", page.page_title) == state["title"]

      assert attributes(html, "form, input, button, turbo-frame, [data-testid], [aria-current]") ==
               attributes(
                 rails,
                 "form, input, button, turbo-frame, [data-testid], [aria-current]"
               )

      refute html =~ "synthetic-a10-reader-secret"
      refute html =~ "phx-submit"
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

  defp attributes(html, selector) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> LazyHTML.to_tree()
    |> Enum.map(fn {tag, attrs, _} ->
      {tag,
       Enum.reject(attrs, fn {name, _} -> String.starts_with?(name, "phx-") end)
       |> Enum.map(fn
         {"class", value} -> {"class", value |> String.split() |> Enum.join(" ")}
         attr -> attr
       end)
       |> Enum.sort()}
    end)
  end
end
