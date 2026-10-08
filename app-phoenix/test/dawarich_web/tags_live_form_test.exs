defmodule DawarichWeb.TagsLiveFormTest do
  use Dawarich.JobsCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.Repo
  alias Dawarich.Test.{FrameSeeds, RailsUser}

  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    %{user: FrameSeeds.user!(8401)}
  end

  defp live_as(user, path),
    do: live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), path)

  defp tag!(user, id, attrs \\ %{}) do
    Repo.insert_all("tags", [
      Map.merge(
        %{
          id: id,
          user_id: user.id,
          name: "Home",
          icon: "☕",
          color: "#123abc",
          created_at: ~N[2026-03-01 10:00:00],
          updated_at: ~N[2026-03-01 10:00:00]
        },
        attrs
      )
    ])
  end

  defp tag_rows(user),
    do:
      Repo.query!(
        "SELECT name, icon, color, privacy_radius_meters, demo FROM tags WHERE user_id=$1 ORDER BY name",
        [user.id]
      ).rows

  defp form(view), do: element(view, "#tag-form")

  defp fill(params),
    do: Map.merge(%{"name" => "Gym", "icon" => "🏋️", "color" => "#ef4444"}, params)

  test "a valid new tag is created and the user lands on the list with the Rails notice", %{
    user: user
  } do
    {:ok, view, _html} = live_as(user, "/tags/new")

    view |> form() |> render_submit(%{"tag" => fill(%{})})

    assert assert_redirect(view, "/tags")["notice"] == "Tag was successfully created."
    assert tag_rows(user) == [["Gym", "🏋️", "#ef4444", nil, false]]
  end

  test "the submit button disables while saving and one submit stores one row", %{user: user} do
    {:ok, view, html} = live_as(user, "/tags/new")
    assert html =~ ~s(phx-disable-with)

    view |> form() |> render_submit(%{"tag" => fill(%{})})
    assert length(tag_rows(user)) == 1
  end

  test "a duplicate name is shown inline and keeps what the user typed", %{user: user} do
    tag!(user, 84011, %{name: "Gym"})
    {:ok, view, _html} = live_as(user, "/tags/new")

    html =
      view
      |> form()
      |> render_submit(%{
        "tag" =>
          fill(%{
            "icon" => "🎾",
            "color" => "#3b82f6",
            "privacy_enabled" => "true",
            "privacy_radius_meters" => "750"
          })
      })

    assert html =~ "Name has already been taken"
    assert has_element?(view, "#tag-form [role=alert]")
    assert has_element?(view, "input[name='tag[name]'][value='Gym']")
    assert has_element?(view, "input[name='tag[icon]'][value='🎾']")
    assert has_element?(view, "input[name='tag[color]'][value='#3b82f6'][checked]")
    assert has_element?(view, "input[name='tag[privacy_radius_meters]'][value='750']")
    assert length(tag_rows(user)) == 1
  end

  test "an invalid radius is reported while typing without saving", %{user: user} do
    {:ok, view, _html} = live_as(user, "/tags/new")

    html =
      view
      |> form()
      |> render_change(%{
        "_target" => ["tag", "privacy_radius_meters"],
        "tag" => fill(%{"privacy_enabled" => "true", "privacy_radius_meters" => "6000"})
      })

    assert html =~ "Privacy radius meters must be less than or equal to 5000"
    assert tag_rows(user) == []
  end

  test "a swatch, a custom color and the untouched default are stored as chosen", %{user: user} do
    {:ok, view, html} = live_as(user, "/tags/new")
    assert html =~ ~s(value="#6ab0a4")

    view
    |> form()
    |> render_change(%{
      "_target" => ["tag", "custom_color"],
      "tag" => fill(%{"color" => "#ef4444", "custom_color" => "#abcdef"})
    })

    assert has_element?(view, "input[name='tag[color]'][value='#abcdef'][checked]")

    view
    |> form()
    |> render_submit(%{"tag" => fill(%{"color" => "#abcdef", "custom_color" => "#abcdef"})})

    assert [["Gym", _, "#abcdef", _, _]] = tag_rows(user)

    {:ok, view, _html} = live_as(user, "/tags/new")

    view
    |> form()
    |> render_submit(%{"tag" => %{"name" => "Default", "icon" => "🏠", "color" => "#6ab0a4"}})

    assert ["Default", _, "#6ab0a4", _, _] = Enum.find(tag_rows(user), &(hd(&1) == "Default"))
  end

  test "privacy on stores 1000 by default and privacy off clears the radius", %{user: user} do
    {:ok, view, _html} = live_as(user, "/tags/new")
    view |> form() |> render_submit(%{"tag" => fill(%{"privacy_enabled" => "true"})})
    assert [[_, _, _, 1000, _]] = tag_rows(user)

    [[id]] = Repo.query!("SELECT id FROM tags WHERE user_id=$1", [user.id]).rows
    {:ok, view, html} = live_as(user, "/tags/#{id}/edit")
    assert html =~ "1000m"

    view |> form() |> render_submit(%{"tag" => fill(%{"privacy_enabled" => "false"})})
    assert [[_, _, _, nil, _]] = tag_rows(user)
  end

  test "the radius label follows the slider while editing", %{user: user} do
    {:ok, view, _html} = live_as(user, "/tags/new")

    html =
      view
      |> form()
      |> render_change(%{
        "_target" => ["tag", "privacy_radius_meters"],
        "tag" => fill(%{"privacy_enabled" => "true", "privacy_radius_meters" => "2350"})
      })

    assert html =~ "2350m"
  end

  test "editing prefills the tag, adopts demo tags and shows the Rails notice", %{user: user} do
    tag!(user, 84012, %{icon: "", color: "", demo: true, privacy_radius_meters: 300})
    {:ok, view, html} = live_as(user, "/tags/84012/edit")

    assert html =~ "Edit Tag"
    assert has_element?(view, "input[name='tag[name]'][value='Home']")
    assert has_element?(view, "input[name='tag[icon]'][value='🏠']")
    assert has_element?(view, "input[name='tag[color]'][value='#6ab0a4'][checked]")
    assert has_element?(view, "input[name='tag[privacy_radius_meters]'][value='300']")

    view
    |> form()
    |> render_submit(%{
      "tag" =>
        fill(%{
          "name" => "Home",
          "icon" => "🏠",
          "color" => "#6ab0a4",
          "privacy_enabled" => "true",
          "privacy_radius_meters" => "300"
        })
    })

    assert assert_redirect(view, "/tags")["notice"] == "Tag was successfully updated."
    assert tag_rows(user) == [["Home", "🏠", "#6ab0a4", 300, false]]
  end

  test "foreign, malformed and oversized ids are not found", %{user: user} do
    foreign = FrameSeeds.user!(8402)
    tag!(foreign, 84013)

    for path <- ["/tags/84013/edit", "/tags/abc/edit", "/tags/#{String.duplicate("9", 30)}/edit"] do
      assert_raise DawarichWeb.NotFoundError, fn -> live_as(user, path) end
    end
  end

  test "a new form starts with one Rails emoji that stays the same after connecting", %{
    user: user
  } do
    conn = get(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), "/tags/new")

    [static] =
      conn.resp_body
      |> LazyHTML.from_document()
      |> LazyHTML.query("input[name='tag[icon]']")
      |> LazyHTML.attribute("value")

    {:ok, view, _html} = live(conn)

    assert has_element?(view, "input[name='tag[icon]'][value='#{static}']")
    source = File.read!(Path.expand("../../../app/helpers/tags_helper.rb", __DIR__))
    [_, list] = Regex.run(~r/COMMON_TAG_EMOJIS = %w\[(.*?)\]/s, source)
    assert static in String.split(list)
  end

  test "values typed before a reconnect come back through form recovery", %{user: user} do
    {:ok, view, html} = live_as(user, "/tags/new")
    assert html =~ ~s(id="tag-form")
    assert html =~ ~s(phx-change="validate")

    view
    |> form()
    |> render_change(%{"_target" => ["tag", "name"], "tag" => fill(%{"name" => "Recovered"})})

    assert has_element?(view, "input[name='tag[name]'][value='Recovered']")
  end

  def handle_query(_event, _measurements, _meta, pid), do: send(pid, :query)

  defp queries(fun) do
    id = "tag-form-queries-#{System.unique_integer([:positive])}"
    :telemetry.attach(id, [:dawarich, :repo, :query], &__MODULE__.handle_query/4, self())
    fun.()
    :telemetry.detach(id)
    count_queries(0)
  end

  defp count_queries(n) do
    receive do
      :query -> count_queries(n + 1)
    after
      0 -> n
    end
  end

  test "opening the forms reads the database no more often than the Rails-era pages", %{
    user: user
  } do
    tag!(user, 84014)

    for {path, budget} <- [{"/tags/new", 4}, {"/tags/84014/edit", 5}] do
      conn = RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id)
      assert queries(fn -> send(self(), {:conn, get(conn, path)}) end) <= budget, path
      assert_received {:conn, conn}
      assert queries(fn -> {:ok, _view, _html} = live(conn) end) <= budget, path
    end
  end

  test "the native form has no Stimulus, island or Rails form plumbing", %{user: user} do
    {:ok, view, page} = live_as(user, "/tags/new")
    html = view |> form() |> render()

    for marker <- [
          "data-controller",
          "data-action",
          "inert",
          "data-rails-form-ready",
          "authenticity_token",
          "data-turbo"
        ],
        do: refute(page =~ marker and html =~ marker, marker)

    assert Regex.scan(~r/phx-update="ignore"/, html) |> length() == 1
    assert html =~ ~s(phx-hook="EmojiPicker")
  end
end
