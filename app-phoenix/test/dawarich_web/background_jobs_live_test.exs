defmodule DawarichWeb.BackgroundJobsLiveTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest, only: [render_component: 2]
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.{ParityHTML, RailsUser}
  alias DawarichWeb.{AdminGate, SettingsLive.BackgroundJobs}

  @tag a10_boundary: :background
  test "background GET mounts after the nonadmin guard" do
    state = Jason.decode!(File.read!("test/fixtures/admin_pages/background_nonadmin.json"))
    row = state["user"]

    RailsUser.insert!(%{
      id: row["id"],
      email: row["email"],
      admin: false,
      settings: row["settings"]
    })

    conn =
      Phoenix.ConnTest.dispatch(
        RailsUser.signed_in(row["id"]),
        DawarichWeb.Endpoint,
        :get,
        "/settings/background_jobs",
        nil
      )

    assert conn.status == 200
    rails = File.read!("test/fixtures/admin_pages/background_nonadmin.html")
    assert ParityHTML.fragment(conn.resp_body, ".min-h-content") == ParityHTML.normalize(rails)
    assert false == String.contains?(conn.resp_body, "href=\"/sidekiq\"")
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    original = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "true")

    on_exit(fn ->
      if original,
        do: System.put_env("SELF_HOSTED", original),
        else: System.delete_env("SELF_HOSTED")
    end)

    :ok
  end

  test "background markup gives nonadmin toggles and admin-only Sidekiq" do
    for name <-
          ~w(admin nonadmin default string_true string_false bool_true bool_false nil queued recalculated neither) do
      Repo.query!("DELETE FROM users", [], log: false)
      state = Jason.decode!(File.read!("test/fixtures/admin_pages/background_#{name}.json"))
      row = state["user"]

      RailsUser.insert!(%{
        id: row["id"],
        email: row["email"],
        admin: row["admin"],
        settings: row["settings"]
      })

      user = Accounts.get(row["id"])
      assert true == AdminGate.background?(RailsUser.signed_in(user.id), %{})

      context = %{
        locale: "en",
        current_user: user,
        self_hosted: true,
        two_factor: false,
        rails_csrf_token: "CSRF"
      }

      page = BackgroundJobs.page(context)
      html = render_component(&BackgroundJobs.render/1, Map.merge(context, page))
      rails = File.read!("test/fixtures/admin_pages/background_#{name}.html")
      actual = ParityHTML.normalize(html)
      expected = ParityHTML.normalize(rails)
      assert actual == expected, ParityHTML.first_difference(actual, expected)
      selector = "a[data-turbo-method], a[target]"
      assert ParityHTML.stimulus(html, selector) == ParityHTML.stimulus(rails, selector)

      assert Enum.count(LazyHTML.query(LazyHTML.from_fragment(html), "a[href='/sidekiq']")) ==
               if(user.admin, do: 1, else: 0)
    end
  end
end
