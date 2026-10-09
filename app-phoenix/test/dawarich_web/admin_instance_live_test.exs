defmodule DawarichWeb.AdminInstanceLiveTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.Repo
  alias Dawarich.Test.RailsUser

  @endpoint DawarichWeb.Endpoint
  @env ~w(DAWARICH_RAILS SELF_HOSTED STORE_GEODATA OIDC_CLIENT_ID OIDC_CLIENT_SECRET)

  defmodule RaisingRepo do
    defdelegate transaction(fun), to: Dawarich.Repo

    def query!(sql, params, opts) do
      if String.starts_with?(sql, "SELECT key,value,encrypted_value FROM instance_settings"),
        do: raise(ArgumentError, "synthetic save crash"),
        else: Dawarich.Repo.query!(sql, params, opts)
    end
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    previous = Map.new(@env, &{&1, System.get_env(&1)})
    System.put_env("DAWARICH_RAILS", "off")
    System.put_env("SELF_HOSTED", "true")
    for key <- ~w(STORE_GEODATA OIDC_CLIENT_ID OIDC_CLIENT_SECRET), do: System.delete_env(key)
    Repo.query!("DELETE FROM instance_settings", [], log: false)
    Dawarich.Experimental.refresh_map_matching(Repo, %{})

    on_exit(fn ->
      Application.delete_env(:dawarich, :admin_instance_opts)
      Dawarich.Experimental.cache_map_matching(Repo, false)

      for {key, value} <- previous,
          do: if(value, do: System.put_env(key, value), else: System.delete_env(key))
    end)

    RailsUser.insert!(%{
      id: 16101,
      email: "native-instance-admin@example.invalid",
      admin: true,
      settings: %{"locale" => "en", "timezone" => "UTC"}
    })

    :ok
  end

  defp live_admin(path \\ "/admin/settings"),
    do: live(RailsUser.signed_in(16101) |> RailsUser.connecting_as(16101), path)

  defp stored,
    do: Repo.query!("SELECT key, value FROM instance_settings ORDER BY key", [], log: false).rows

  defp server_html(view),
    do: rendered_to_string(view.module.render(:sys.get_state(view.pid).socket.assigns))

  defp submit(view, section, settings) do
    view
    |> form("[data-testid=instance-settings-form-#{section}]")
    |> render_submit(%{"section" => section, "instance_settings" => settings})
  end

  test "section links patch the URL and show that section" do
    {:ok, view, _} = live_admin()

    view |> element("[data-testid=instance-settings-section-nominatim]") |> render_click()
    assert_patch(view, "/admin/settings?section=nominatim")
    assert has_element?(view, "#instance_settings_nominatim_api_host")
  end

  test "an unknown section falls back to the active provider" do
    {:ok, view, _} = live_admin("/admin/settings?section=nope")
    assert has_element?(view, "#instance_settings_photon_api_host")
  end

  test "saving a section stores it and shows the saved notice" do
    {:ok, view, _} = live_admin("/admin/settings?section=points")

    assert submit(view, "points", %{"store_geodata" => "false"}) =~ "Settings saved."
    assert stored() == [["store_geodata", false]]
  end

  test "pinned and invalid inputs show the existing alerts and store nothing" do
    System.put_env("STORE_GEODATA", "true")
    {:ok, view, _} = live_admin("/admin/settings?section=points")

    assert submit(view, "points", %{"store_geodata" => "false"}) =~
             "Refused: pinned by STORE_GEODATA."

    {:ok, view, _} = live_admin("/admin/settings?section=photon")

    assert submit(view, "photon", %{"photon_api_host" => "bad host"}) =~
             "The host must be a bare hostname"

    assert stored() == []
  end

  test "a typed secret is never echoed or kept and the form starts empty after saving" do
    {:ok, view, _} = live_admin("/admin/settings?section=geoapify")
    before = view |> element("[data-testid=instance-settings-form-geoapify]") |> render()

    submit(view, "geoapify", %{"geoapify_api_key" => "synthetic-typed-geoapify-key"})

    refute server_html(view) =~ "synthetic-typed-geoapify-key"
    refute inspect(:sys.get_state(view.pid), limit: :infinity) =~ "synthetic-typed-geoapify-key"
    refute view |> element("[data-testid=instance-settings-form-geoapify]") |> render() == before
  end

  test "the Atlas test runs once in the background and a timeout shows the failure alert" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listener)
    owner = self()

    spawn_link(fn ->
      for _ <- 1..2 do
        {:ok, socket} = :gen_tcp.accept(listener)
        send(owner, {:atlas_connection, socket})
      end
    end)

    Repo.query!(
      "INSERT INTO instance_settings(key, value, created_at, updated_at) VALUES('atlas_url', $1, now(), now())",
      ["http://127.0.0.1:#{port}"]
    )

    {:ok, view, _} = live_admin("/admin/settings?section=experimental")

    view |> element("#test-map-matching") |> render_click()
    assert has_element?(view, "#test-map-matching[disabled]")
    render_hook(view, "test_map_matching", %{})

    assert_receive {:atlas_connection, _}, 2000
    refute_receive {:atlas_connection, _}, 300

    send(view.pid, {:admin_async_timeout, :map_matching})
    assert render(view) =~ "Atlas connection failed (timeout)."
    refute has_element?(view, "#test-map-matching[disabled]")
  end

  test "the Atlas test without a URL shows the not-configured alert" do
    {:ok, view, _} = live_admin("/admin/settings?section=experimental")

    view |> element("#test-map-matching") |> render_click()
    assert render_async(view) =~ "Save an Atlas URL first."
  end

  test "an OIDC instance shows the page but refuses saving" do
    System.put_env("OIDC_CLIENT_ID", "synthetic-client")
    System.put_env("OIDC_CLIENT_SECRET", "synthetic-secret")
    {:ok, view, _} = live_admin("/admin/settings?section=points")

    assert submit(view, "points", %{"store_geodata" => "false"}) =~
             "not available on instances that sign in through OIDC or Google"

    assert stored() == []
  end

  test "a non-admin cannot open the page" do
    Repo.query!("UPDATE users SET admin = false WHERE id = 16101")

    conn =
      get(RailsUser.signed_in(16101) |> RailsUser.connecting_as(16101), "/admin/settings")

    assert conn.status == 404
  end

  test "a crashing save shows the generic alert and keeps the page alive" do
    {:ok, view, _} = live_admin("/admin/settings?section=points")
    Application.put_env(:dawarich, :admin_instance_opts, repo: RaisingRepo)

    assert submit(view, "points", %{"store_geodata" => "false"}) =~
             "Something went wrong. Please try again."

    assert Process.alive?(view.pid)
  end

  test "the page stays within the inventory query budget plus the admission read" do
    {conn, static} =
      queries(fn ->
        get(RailsUser.signed_in(16101) |> RailsUser.connecting_as(16101), "/admin/settings")
      end)

    {_, connected} = queries(fn -> {:ok, _view, _} = live(conn) end)
    assert static <= 19
    assert connected <= 17 + 1
  end

  def handle_query(_event, _measurements, _meta, pid), do: send(pid, :query)

  defp queries(fun) do
    id = "admin-instance-budget-#{System.unique_integer([:positive])}"
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
end
