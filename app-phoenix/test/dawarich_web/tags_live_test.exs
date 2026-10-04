defmodule DawarichWeb.TagsLiveTest do
  use Dawarich.JobsCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
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

  test "tag index matches badges counts links and delete button form", %{user: user} do
    tag!(user, 83911, %{icon: "☕", color: "#123abc", privacy_radius_meters: 750})
    FrameSeeds.place!(user.id, 839_101, "Synthetic")

    Repo.insert_all("taggings", [
      %{
        tag_id: 83911,
        taggable_id: 839_101,
        taggable_type: "Place",
        created_at: ~N[2026-03-01 10:00:00],
        updated_at: ~N[2026-03-01 10:00:00]
      }
    ])

    {:ok, _view, html} = live_as(user, "/tags")
    assert html =~ "#Home &amp; &lt;café&gt;"
    assert html =~ "750m"
    assert attr(html, "tbody tr td.text-right.tabular-nums", "class") != []
    assert attr(html, "a[href='/tags/83911/edit']", "class") == ["btn btn-ghost btn-xs"]
    assert attr(html, "form[action='/tags/83911']", "method") == ["post"]
    assert attr(html, "form[action='/tags/83911'] input[name='_method']", "value") == ["delete"]
    assert attr(html, "form button", "data-turbo-method") == ["delete"]
    assert attr(html, "form button", "data-turbo-confirm") == ["Are you sure?"]
    assert attr(html, "form[action='/tags/83911']", "phx-submit") == []
  end

  test "new form defaults come from the Rails emoji set and are stable within a mount", %{
    user: user
  } do
    assert %{plug: Phoenix.LiveView.Plug} =
             Phoenix.Router.route_info(Router, "GET", "/tags/new", "localhost")

    conn = get(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), "/tags/new")
    static_emoji = attr(conn.resp_body, "input[name='tag[icon]']", "value")
    {:ok, view, html} = live(conn)
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

    assert %{pipe_through: [:browser, :rails_user], rails_gate: {MapDataGate, :tags?}} =
             Phoenix.Router.route_info(Router, "GET", "/tags", "localhost")

    assert %{rails_gate: {MapDataGate, :tag_edit?}} =
             Phoenix.Router.route_info(Router, "GET", "/tags/83941/edit", "localhost")

    refute MapDataGate.tag_edit?(conn, %{"id" => "83941"})
    refute MapDataGate.tag_edit?(conn, %{"id" => "999999"})

    for id <- ["bad", "1e3", "1abc", "9999999999999999999"],
        do: refute(MapDataGate.tag_edit?(conn, %{"id" => id}))

    for query <- ["locale=de", "client=x", "aff=x", "via=x", "tag[name]=x", "format=json"],
        do: refute(MapDataGate.tags?(%{conn | query_string: query}, %{}))

    refute MapDataGate.tags?(put_req_header(conn, "x-dawarich-client", "test"), %{})

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
