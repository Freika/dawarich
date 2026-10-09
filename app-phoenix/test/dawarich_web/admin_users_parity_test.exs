defmodule DawarichWeb.AdminUsersParityTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest, only: [render_component: 2]
  import Dawarich.Test.FormIsolation
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.{ParityHTML, RailsUser}
  alias DawarichWeb.SettingsLive.{UsersIndex, UserShow, UserEdit}

  @dir "test/fixtures/admin_users"
  @cases ~w(list list_page2 list_out list_literal list_empty registration_disabled)

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  test "client-owned admin and extraction dialogs ignore LiveView child patches" do
    admin =
      render_component(&DawarichWeb.AdminUserDialogs.dialogs/1,
        locale: "en",
        rows: [%{id: 2, email: "dialog@dawarich.test"}],
        actor: %{id: 1},
        rails_csrf_token: "synthetic-csrf"
      )

    extraction =
      render_component(&DawarichWeb.ImportsExtractionDialog.dialog/1,
        id: 3,
        locale: "en",
        csrf: "synthetic-csrf"
      )

    dialogs = LazyHTML.from_fragment(admin <> extraction) |> LazyHTML.query("dialog")

    assert LazyHTML.attribute(dialogs, "id") == [
             "create_user",
             "delete_user_2",
             "extraction-dialog-3"
           ]

    assert LazyHTML.attribute(dialogs, "phx-update") == ["ignore", "ignore", "ignore"]
    assert LazyHTML.attribute(dialogs, "open") == []
    assert_form_isolated(admin)
    assert_form_isolated(extraction)
  end

  for name <- @cases do
    @name name
    @tag a10_users: String.to_atom(@name)
    test "user list #{@name} matches Rails" do
      state = fixture(@name)
      context = seed!(state)
      params = URI.decode_query(URI.parse(state["path"]).query || "")
      assert {:ok, page} = UsersIndex.page(params, context)

      html =
        render_component(
          &UsersIndex.render/1,
          Map.merge(context, Map.merge(page, %{create_email: "", form_version: 0}))
        )

      ids =
        LazyHTML.from_fragment(html)
        |> LazyHTML.query("tbody tr")
        |> LazyHTML.attribute("data-user-id")

      assert ids == Enum.map(state["visible_ids"], &to_string/1)
      assert page.data.search == params["search"]
      assert page.data.registration == state["registration"]
      assert DawarichWeb.Layouts.page_title("en", page.page_title) == state["title"]

      for row <- page.data.rows do
        assert html =~ row.email
        refute row.status == 3 and html =~ "Pending payment"
      end
    end
  end

  @tag a10_users: :show
  test "user show matches Rails and keeps clipboard key out of LiveView session" do
    for name <- ~w(show_self show_target) do
      state = fixture(name)
      context = seed_detail!(state)
      assert {:ok, page} = UserShow.page(%{"id" => to_string(state["target"]["id"])}, context)
      html = render_component(&UserShow.render/1, Map.merge(context, page))
      assert_markup!(html, name)
      button = LazyHTML.from_fragment(html) |> LazyHTML.query("[data-controller='clipboard']")

      assert LazyHTML.attribute(button, "data-clipboard-text-value") == [
               state["target"]["api_key"]
             ]

      assert LazyHTML.attribute(button, "data-action") == ["click->clipboard#copy"]

      assert html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query(
               "#admin-user-clipboard[phx-hook='RailsStimulus'] [data-controller='clipboard']"
             )
             |> Enum.count() == 1

      conn = %{Plug.Test.conn(:get, state["path"]) | assigns: Map.merge(context, page)}
      session = DawarichWeb.RailsAuth.live_session(conn)
      assert false == String.contains?(Jason.encode!(session), state["target"]["api_key"])
      assert DawarichWeb.Layouts.page_title("en", page.page_title) == state["title"]
    end
  end

  @tag a10_users: :edit
  test "user edit posts blank-password and status controls to Rails" do
    for name <- ~w(edit_self edit_target) do
      state = fixture(name)
      context = seed_detail!(state)
      assert {:ok, page} = UserEdit.page(%{"id" => to_string(state["target"]["id"])}, context)
      html = render_component(&UserEdit.render/1, Map.merge(context, page))
      assert_form_isolated(html, "form.edit_user")
      assert_markup!(html, name)
      password = LazyHTML.from_fragment(html) |> LazyHTML.query("input[type='password']")
      assert LazyHTML.attribute(password, "value") in [[], [""]]
      assert LazyHTML.attribute(password, "autocomplete") == ["new-password"]
      refute html =~ "phx-submit"
    end
  end

  @tag a10_users: :status
  test "user edit submits exact named status options with translated labels and target selected" do
    for {name, status} <- Enum.with_index(~w(inactive active trial pending_payment)) do
      fixture_name = "edit_" <> name
      state = fixture(fixture_name)
      context = seed_detail!(state)
      assert {:ok, page} = UserEdit.page(%{"id" => to_string(state["target"]["id"])}, context)
      html = render_component(&UserEdit.render/1, Map.merge(context, page))

      options =
        LazyHTML.from_fragment(html) |> LazyHTML.query("select[name='user[status]'] option")

      assert LazyHTML.attribute(options, "value") == ~w(inactive active trial pending_payment)

      assert Enum.map(options, &(LazyHTML.text(&1) |> String.trim())) == [
               "Inactive",
               "Active",
               "Trial",
               "Pending payment"
             ]

      assert LazyHTML.from_fragment(html)
             |> LazyHTML.query("option[selected]")
             |> LazyHTML.attribute("value") == [
               Enum.at(~w(inactive active trial pending_payment), status)
             ]

      assert_markup!(html, fixture_name)
    end
  end

  defp assert_markup!(html, name) do
    rails = File.read!(Path.join(@dir, name <> ".html"))
    actual = ParityHTML.normalize(String.replace(html, ~s( id="admin-user-clipboard"), ""))
    expected = ParityHTML.normalize(rails)
    assert actual == expected, ParityHTML.first_difference(actual, expected)
    assert attributes(html) == attributes(rails)
  end

  defp seed_detail!(state) do
    for table <- ~w(areas imports exports tracks users),
        do: Repo.query!("DELETE FROM " <> table, [], log: false)

    context = seed!(state)
    row = state["target"]

    if Map.has_key?(row, "api_key") do
      Repo.query!(
        "UPDATE users SET api_key = $1, sign_in_count = $2, last_sign_in_ip = $3, current_sign_in_ip = $4 WHERE id = $5",
        [
          row["api_key"],
          row["sign_in_count"],
          row["last_sign_in_ip"],
          row["current_sign_in_ip"],
          row["id"]
        ],
        log: false
      )
    end

    counts = row["counts"] || %{}

    for table <- ~w(imports exports), _ <- 1..(counts[table] || 0)//1 do
      Repo.insert_all(table, [
        %{
          user_id: row["id"],
          name: "Synthetic",
          created_at: ~N[2026-10-03 10:00:00],
          updated_at: ~N[2026-10-03 10:00:00]
        }
      ])
    end

    for _ <- 1..(counts["tracks"] || 0)//1 do
      Repo.query!(
        "INSERT INTO tracks(user_id, start_at, end_at, original_path, created_at, updated_at) VALUES($1,'2026-10-03 09:00:00','2026-10-03 10:00:00',ST_GeomFromText('LINESTRING(0 0,0.001 0.001)',4326),'2026-10-03 10:00:00','2026-10-03 10:00:00')",
        [row["id"]],
        log: false
      )
    end

    for _ <- 1..(counts["areas"] || 0)//1 do
      Repo.insert_all("areas", [
        %{
          user_id: row["id"],
          name: "Synthetic",
          radius: 100,
          latitude: 0.0,
          longitude: 0.0,
          created_at: ~N[2026-10-03 10:00:00],
          updated_at: ~N[2026-10-03 10:00:00]
        }
      ])
    end

    context
  end

  defp fixture(name), do: Jason.decode!(File.read!(Path.join(@dir, name <> ".json")))

  defp seed!(state) do
    rows =
      if state["rows"] == [],
        do: Enum.uniq_by([state["user"], state["target"]], & &1["id"]),
        else: state["rows"]

    for row <- rows do
      RailsUser.insert!(%{
        id: row["id"],
        email: row["email"],
        admin: row["admin"],
        settings: row["settings"],
        status: row["status"],
        points_count: row["points_count"],
        created_at: naive(row["created_at"]),
        last_sign_in_at: naive(row["last_sign_in_at"])
      })
    end

    Dawarich.State.put_registration_enabled(Repo, state["registration"])

    %{
      locale: "en",
      current_user: Accounts.get(state["user"]["id"]),
      current_scope: Dawarich.Accounts.Scope.for_user(Accounts.get(state["user"]["id"]), "en"),
      rails_csrf_token: "CSRF",
      self_hosted: true,
      two_factor: false
    }
  end

  defp naive(nil), do: nil
  defp naive(value), do: value |> DateTime.from_iso8601() |> elem(1) |> DateTime.to_naive()

  defp attributes(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("form, input, button, dialog, select, option, [onclick]")
    |> LazyHTML.to_tree()
    |> Enum.map(fn {tag, attrs, _} ->
      {tag,
       attrs
       |> Enum.reject(fn
         {"id", "phx-" <> _} -> true
         {name, _} -> String.starts_with?(name, "phx-")
       end)
       |> Enum.map(fn
         {"class", value} -> {"class", value |> String.split() |> Enum.join(" ")}
         attr -> attr
       end)
       |> Enum.sort()}
    end)
  end
end
