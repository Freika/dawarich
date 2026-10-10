defmodule DawarichWeb.AdminUsersParityTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest, only: [render_component: 2]
  import Dawarich.Test.FormIsolation
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.SettingsLive.{UsersIndex, UserShow, UserEdit}

  @dir "test/fixtures/admin_users"
  @cases ~w(list list_page2 list_out list_literal list_empty registration_disabled)

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    :ok
  end

  test "unmigrated extraction dialog keeps its isolated HTTP behavior" do
    html =
      render_component(&DawarichWeb.ImportsExtractionDialog.dialog/1,
        id: 3,
        locale: "en",
        csrf: "synthetic-csrf"
      )

    assert LazyHTML.attribute(
             LazyHTML.query(LazyHTML.from_fragment(html), "dialog"),
             "phx-update"
           ) == ["ignore"]

    assert_form_isolated(html)
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
          Map.merge(
            context,
            Map.merge(page, %{create_email: "", form_version: 0, delete_id: nil, flash: %{}})
          )
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

      html =
        render_component(
          &UserShow.render/1,
          Map.merge(
            context,
            Map.merge(page, %{
              security_accepted: MapSet.new(),
              rotate_pending: false,
              dialog_open: false
            })
          )
        )

      assert page.target.id == state["target"]["id"]
      assert page.target.email == state["target"]["email"]
      assert page.counts == state["target"]["counts"]
      assert page.target.points_count == state["target"]["points_count"]
      assert page.target.sign_in_count == state["target"]["sign_in_count"]
      assert page.target.last_sign_in_ip == state["target"]["last_sign_in_ip"]
      assert page.target.current_sign_in_ip == state["target"]["current_sign_in_ip"]

      button =
        LazyHTML.from_fragment(html) |> LazyHTML.query("#admin-user-copy[phx-hook=Clipboard]")

      assert LazyHTML.attribute(button, "data-clipboard-text") == [state["target"]["api_key"]]
      assert html =~ String.slice(state["target"]["api_key"], 0, 8) <> String.duplicate("•", 24)

      assert page.target.created_at ==
               Dawarich.UserTimeZone.local(
                 state["user"]["settings"],
                 naive(state["target"]["created_at"])
               )

      refute Map.has_key?(page.target, :api_key)
      assert page.target_user.encrypted_password == nil

      conn = %{Plug.Test.conn(:get, state["path"]) | assigns: Map.merge(context, page)}
      session = DawarichWeb.RailsAuth.live_session(conn)
      assert false == String.contains?(Jason.encode!(session), state["target"]["api_key"])
      assert DawarichWeb.Layouts.page_title("en", page.page_title) == state["title"]
    end
  end

  @tag a10_users: :edit
  test "user edit exposes redacted values and blank credential fields" do
    for name <- ~w(edit_self edit_target) do
      state = fixture(name)
      context = seed_detail!(state)
      assert {:ok, page} = UserEdit.page(%{"id" => to_string(state["target"]["id"])}, context)
      html = render_component(&UserEdit.render/1, Map.merge(context, page))
      assert page.target.email == state["target"]["email"]
      assert page.target.admin == state["target"]["admin"]
      assert page.target.status == state["target"]["status"]
      refute Map.has_key?(page.target, :api_key)
      refute Map.has_key?(page.target, :encrypted_password)
      assert html =~ "phx-submit=\"update_user\""
      password = LazyHTML.from_fragment(html) |> LazyHTML.query("input[type='password']")
      assert LazyHTML.attribute(password, "value") in [[], [""]]
      assert LazyHTML.attribute(password, "autocomplete") == ["new-password"]
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
    end
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
      form_version: 0,
      current_user: Accounts.get(state["user"]["id"]),
      current_scope: Dawarich.Accounts.Scope.for_user(Accounts.get(state["user"]["id"]), "en"),
      rails_csrf_token: "CSRF",
      self_hosted: true,
      two_factor: false
    }
  end

  defp naive(nil), do: nil
  defp naive(value), do: value |> DateTime.from_iso8601() |> elem(1) |> DateTime.to_naive()
end
