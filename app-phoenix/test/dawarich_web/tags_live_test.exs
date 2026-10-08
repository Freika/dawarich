defmodule DawarichWeb.TagsLiveTest do
  use Dawarich.JobsCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Dawarich.Test.FormIsolation
  import Plug.Conn
  alias Dawarich.Repo
  alias Dawarich.Test.{FrameSeeds, RailsUser}
  alias DawarichWeb.{MapDataGate, Router}

  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    %{user: FrameSeeds.user!(8391)}
  end

  defp tag!(user, id, attrs \\ %{}) do
    Repo.insert_all("tags", [
      Map.merge(
        %{
          id: id,
          user_id: user.id,
          name: "Home & <café>",
          created_at: ~N[2026-03-01 10:00:00],
          updated_at: ~N[2026-03-01 10:00:00]
        },
        attrs
      )
    ])
  end

  defp live_as(user, path) do
    assert %{plug: Phoenix.LiveView.Plug} =
             Phoenix.Router.route_info(Router, "GET", path, "localhost")

    live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), path)
  end

  defp attr(html, selector, name),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> LazyHTML.attribute(name)

  defp place_tagging!(user, tag_id, place_id) do
    FrameSeeds.place!(user.id, place_id, "Synthetic")

    Repo.insert_all("taggings", [
      %{
        tag_id: tag_id,
        taggable_id: place_id,
        taggable_type: "Place",
        created_at: ~N[2026-03-01 10:00:00],
        updated_at: ~N[2026-03-01 10:00:00]
      }
    ])
  end

  defp native_clean?(html) do
    not Enum.any?(
      [
        "data-turbo",
        "data-controller",
        "turbo-frame",
        "RailsStimulus",
        "/phoenix/js/",
        "importmap"
      ],
      &String.contains?(html, &1)
    )
  end

  test "a guest is sent to sign in and comes back to tags afterwards" do
    conn = get(Phoenix.ConnTest.build_conn(), "/tags")

    assert redirected_to(conn) =~ "/users/sign_in"
    assert Dawarich.Test.RailsFormRequests.rails_session(conn)["user_return_to"] == "/tags"
  end

  test "the native index lists own tags with icon, color, radius and place count", %{user: user} do
    tag!(user, 83911, %{icon: "☕", color: "#123abc", privacy_radius_meters: 750})
    place_tagging!(user, 83911, 839_101)
    foreign = FrameSeeds.user!(8396)
    tag!(foreign, 83912, %{name: "Foreign secret"})

    {:ok, view, html} = live_as(user, "/tags")
    row = view |> element("#tags-83911") |> render()

    assert row =~ "#Home &amp; &lt;café&gt;"
    assert row =~ "☕"
    assert row =~ "#123abc"
    assert row =~ "750m"
    assert row =~ ~r/>\s*1\s*</
    refute html =~ "Foreign secret"
    assert native_clean?(html)

    assert %Dawarich.Accounts.Scope{user: %{id: id}, locale: "en"} =
             :sys.get_state(view.pid).socket.assigns.current_scope

    assert id == user.id
  end

  test "deleting a tag removes the row, its taggings and shows the Rails notice", %{user: user} do
    tag!(user, 83913)
    tag!(user, 83914, %{name: "Second"})
    place_tagging!(user, 83913, 839_102)
    {:ok, view, _html} = live_as(user, "/tags")

    html = view |> element("#tags-83913 button[phx-click='delete']") |> render_click()

    refute has_element?(view, "#tags-83913")
    assert has_element?(view, "#tags-83914")
    assert html =~ "Tag was successfully deleted."
    assert Repo.query!("SELECT count(*) FROM taggings WHERE tag_id=83913").rows == [[0]]
  end

  test "deleting the last tag shows the empty state without a reload", %{user: user} do
    tag!(user, 83915)
    {:ok, view, html} = live_as(user, "/tags")
    refute html =~ "No tags yet"

    view |> element("#tags-83915 button[phx-click='delete']") |> render_click()

    assert render(view) =~ "No tags yet"
  end

  test "forged delete ids change nothing and keep the page alive", %{user: user} do
    foreign = FrameSeeds.user!(8397)
    tag!(foreign, 83916)
    tag!(user, 83917)
    {:ok, view, _html} = live_as(user, "/tags")

    for id <- ["83916", "abc", "99999999999999999999"],
        do: render_click(view, "delete", %{"id" => id})

    assert has_element?(view, "#tags-83917")
    assert Repo.query!("SELECT count(*) FROM tags WHERE id IN (83916, 83917)").rows == [[2]]
  end

  test "a Rails redirect flash appears on the native page and closes on click", %{user: user} do
    flash = %{"flash" => %{"discard" => [], "flashes" => %{"notice" => "Saved by Rails"}}}
    conn = RailsUser.signed_in(user.id, flash) |> RailsUser.connecting_as(user.id)
    {:ok, view, html} = live(conn, "/tags")

    assert html =~ "Saved by Rails"
    view |> element("#flash-messages [role=alert] button") |> render_click()
    refute render(view) =~ "Saved by Rails"
  end

  test "signing out in another tab ends the native session on the next event", %{user: user} do
    tag!(user, 83918)
    session = RailsUser.session(user.id)

    conn =
      Phoenix.ConnTest.build_conn()
      |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))

    {:ok, view, _html} = live(RailsUser.connecting_as(conn, user.id), "/tags")

    DawarichWeb.NotificationSession.signed_out(session)

    assert {:error, {:redirect, %{to: "/users/sign_in"}}} =
             view |> element("#tags-83918 button[phx-click='delete']") |> render_click()
  end

  test "a reconnect carrying another user's session is refused", %{user: user} do
    other = FrameSeeds.user!(8398)
    conn = RailsUser.signed_in(user.id) |> RailsUser.connecting_as(other.id)

    assert {:error, {:redirect, %{to: "/users/sign_in"}}} = live(conn, "/tags")
  end

  test "the changelog consent prompt on a native page stores the decision", %{user: user} do
    {:ok, view, html} = live_as(user, "/tags")
    assert html =~ "changelog_consent"

    view
    |> element("form[phx-submit='changelog_consent']:has(input[value='granted'])")
    |> render_submit()

    assert Repo.query!("SELECT changelog_consent FROM users WHERE id=$1", [user.id]).rows != [
             [nil]
           ]

    refute render(view) =~ ~s(phx-submit="changelog_consent")
  end

  test "a Turbo visit from a hybrid page gets the reload document", %{user: user} do
    conn =
      RailsUser.signed_in(user.id) |> put_req_header("x-turbo-request-id", "1") |> get("/tags")

    assert conn.resp_body =~ "turbo-visit-control"
  end

  test "new form defaults come from the Rails emoji set and are stable within a mount", %{
    user: user
  } do
    assert %{plug: Phoenix.LiveView.Plug} =
             Phoenix.Router.route_info(Router, "GET", "/tags/new", "localhost")

    conn = get(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), "/tags/new")
    static_emoji = attr(conn.resp_body, "input[name='tag[icon]']", "value")
    assert_form_isolated(conn.resp_body, "form.space-y-4")
    {:ok, view, html} = live(conn)
    assert_form_isolated(html, "form.space-y-4")
    [emoji] = attr(html, "input[name='tag[icon]']", "value")
    source = File.read!(Path.expand("../../../app/helpers/tags_helper.rb", __DIR__))
    [_, list] = Regex.run(~r/COMMON_TAG_EMOJIS = %w\[(.*?)\]/s, source)
    assert emoji in String.split(list)
    assert static_emoji == [emoji]
    assert attr(render(view), "input[name='tag[icon]']", "value") == [emoji]
    assert attr(html, "input[name='tag[color]']", "value") == ["#6ab0a4"]
    assert attr(html, "form.space-y-4", "action") == ["/tags"]
    assert attr(html, "form.space-y-4 input[name='_method']", "value") == []
    assert attr(html, "#tag-fields-new[phx-hook='RailsStimulus']", "phx-update") == ["ignore"]
  end

  test "edit form preserves exact Rails field names methods and blank defaults", %{user: user} do
    tag!(user, 83921, %{icon: "", color: "", demo: true})
    {:ok, _view, html} = live_as(user, "/tags/83921/edit")
    assert_form_isolated(html, "form.space-y-4")
    assert attr(html, "form.space-y-4", "action") == ["/tags/83921"]
    assert attr(html, "form.space-y-4", "method") == ["post"]
    assert attr(html, "form.space-y-4 input[name='_method']", "value") == ["patch"]
    assert attr(html, "input[name='tag[name]']", "value") == ["Home & <café>"]
    assert attr(html, "input[name='tag[icon]']", "value") == ["🏠"]
    assert attr(html, "input[name='tag[color]']", "value") == ["#6ab0a4"]

    assert attr(html, "input[name='tag[privacy_radius_meters]']", "id") == [
             "tag_privacy_radius_meters"
           ]

    assert length(attr(html, "form.space-y-4 input[name='authenticity_token']", "value")) == 1
    assert attr(html, "form.space-y-4 input[name='commit']", "value") == ["Update Tag"]
    assert attr(html, "form.space-y-4", "phx-change") == []

    assert attr(html, "[data-controller='emoji-picker']", "data-emoji-picker-auto-submit-value") ==
             ["false"]

    assert attr(html, "[data-color-picker-target='swatch']", "data-color") |> length() == 18
  end

  test "tag name and picker values share the client-owned form island", %{user: user} do
    tag!(user, 83922)

    conn =
      get(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), "/tags/83922/edit")

    assert attr(conn.resp_body, "#tag-fields-83922 input[name='tag[name]']", "value") == [
             "Home & <café>"
           ]

    {:ok, _view, html} = live(conn)
    assert attr(html, "#tag-fields-83922", "phx-update") == ["ignore"]
    assert attr(html, "#tag-fields-83922 input[name='tag[name]']", "value") == ["Home & <café>"]
    assert attr(html, "#tag-fields-83922 input[name='tag[color]']", "id") == ["tag_color"]
  end

  test "form islands wait for their controllers before accepting input", %{user: user} do
    for path <- ["/tags/new", "/points"] do
      conn = get(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), path)
      assert attr(conn.resp_body, "[phx-hook='RailsStimulus']", "inert") == [""]
      assert attr(conn.resp_body, "fieldset[data-rails-form-ready]", "disabled") == [""]
    end
  end

  test "privacy controls mirror enabled and disabled states", %{user: user} do
    tag!(user, 83931)
    {:ok, _view, html} = live_as(user, "/tags/83931/edit")
    assert attr(html, "[data-privacy-radius-target='toggle']", "checked") == []

    assert attr(html, "[data-privacy-radius-target='radiusInput']", "class") == [
             "form-control hidden"
           ]

    assert attr(html, "[data-privacy-radius-target='slider']", "value") == ["1000"]
    Repo.query!("UPDATE tags SET privacy_radius_meters = 750 WHERE id = 83931")
    {:ok, _view, html} = live_as(user, "/tags/83931/edit")
    assert attr(html, "[data-privacy-radius-target='toggle']", "checked") != []
    assert attr(html, "[data-privacy-radius-target='radiusInput']", "class") == ["form-control"]
    assert attr(html, "input[name='tag[privacy_radius_meters]']", "value") == ["750"]
    assert attr(html, "[data-privacy-radius-target='slider']", "min") == ["50"]
    assert attr(html, "[data-privacy-radius-target='slider']", "max") == ["5000"]
  end

  test "foreign edit malformed ids and writers reach Rails", %{user: user} do
    foreign = FrameSeeds.user!(8392)
    tag!(foreign, 83941)
    conn = RailsUser.signed_in(user.id)

    assert %{rails_gate: {MapDataGate, :tag_edit?}} =
             Phoenix.Router.route_info(Router, "GET", "/tags/83941/edit", "localhost")

    assert MapDataGate.tag_edit?(conn, %{"id" => "83941"})
    assert MapDataGate.tag_edit?(conn, %{"id" => "999999"})

    for id <- ["bad", "1e3", "1abc", "9999999999999999999"],
        do: refute(MapDataGate.tag_edit?(conn, %{"id" => id}))

    for method <- ["POST", "PATCH", "PUT", "DELETE"] do
      if method == "POST",
        do:
          assert(
            %{plug: DawarichWeb.TagActions} =
              Phoenix.Router.route_info(Router, method, "/tags", "localhost")
          ),
        else: assert(:error = Phoenix.Router.route_info(Router, method, "/tags", "localhost"))

      assert %{plug: DawarichWeb.TagActions} =
               Phoenix.Router.route_info(Router, method, "/tags/83941", "localhost")
    end
  end
end
