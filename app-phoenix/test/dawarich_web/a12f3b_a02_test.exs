defmodule DawarichWeb.A12f3bA02Test do
  use Dawarich.DataCase, async: false
  import Plug.Conn
  import Phoenix.ConnTest
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.AchievementPublicPage
  alias Dawarich.Sharing

  setup do
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    Dawarich.Test.AchievementSilhouettes.clear()
    on_exit(&Dawarich.Test.AchievementSilhouettes.clear/0)

    RailsUser.insert!(%{
      id: 81302,
      email: "achievement-public-tail@example.invalid",
      settings: %{"locale" => "en", "timezone" => "Pacific/Chatham"}
    })

    :ok
  end

  @tag a12f3b_case: "A02a"
  test "native A02a achievement sharing preserves independently public embeds" do
    session = RailsUser.session(81302)
    assert {:ok, %{uuid: uuid}} = change(%{"enabled" => true})
    url = "/shared/achievements/" <> uuid

    owner =
      build_conn("GET", url <> "?locale=de&embed=1")
      |> put_req_header("accept", "text/html")
      |> Plug.Test.put_req_cookie("_dawarich_session", RailsUser.cookie(session))

    page = AchievementPublicPage.call(owner, [])
    assert page.status == 200
    assert page.resp_body =~ ~s(lang="de")
    assert get_resp_header(page, "content-security-policy") == ["frame-ancestors *"]
    assert get_resp_header(page, "x-frame-options") == []
    assert query_rows("SELECT settings->>'locale' FROM users WHERE id=81302") == [["de"]]
    assert AchievementPublicPage.call(build_conn("HEAD", url <> "?embed=1"), []).resp_body == ""

    assert {:ok, %{enabled: false}} = change(%{"enabled" => "false"})

    assert AchievementPublicPage.call(build_conn("GET", url <> "?embed=1"), []).status == 302
    assert {:ok, %{uuid: ^uuid}} = change(%{"enabled" => true})
    assert AchievementPublicPage.call(build_conn("GET", url <> "?embed=1"), []).status == 200

    assert AchievementPublicPage.call(build_conn("GET", "/shared/achievements/unknown"), []).status ==
             302

    assert {:error, :invalid_input} = change(%{"enabled" => nil})
    assert query_rows("SELECT count(*) FROM achievement_progresses WHERE user_id=81302") == [[1]]
  end

  @tag :fix_ach_image_params
  test "public achievement cards ignore crawler query keys and preserve locale and embeds" do
    assert {:ok, %{uuid: uuid}} = change(%{"enabled" => true})
    path = "/shared/achievements/" <> uuid

    for query <- [
          "utm_source=x&release_probe=y",
          "%75tm_source=x",
          "utm_source=x&utm_source=y",
          "utm_source[a]=x"
        ] do
      page = AchievementPublicPage.call(build_conn("GET", path <> "?embed=1&" <> query), [])
      assert page.status == 200, query
      assert page.resp_body =~ "ach-embed-page"
      assert page.resp_body =~ ~s(lang="en")
      assert get_resp_header(page, "content-security-policy") == ["frame-ancestors *"]
      assert get_resp_header(page, "x-frame-options") == []
      head = AchievementPublicPage.call(build_conn("HEAD", path <> "?embed=1&" <> query), [])
      assert head.status == 200 and head.resp_body == ""

      missing =
        AchievementPublicPage.call(
          build_conn("GET", "/shared/achievements/unknown?" <> query),
          []
        )

      assert missing.status == 302
    end

    owner =
      build_conn("GET", path <> "?locale=de&embed=1&utm_source=x")
      |> Plug.Test.put_req_cookie("_dawarich_session", RailsUser.cookie(RailsUser.session(81302)))

    page = AchievementPublicPage.call(owner, [])
    assert page.status == 200 and page.resp_body =~ ~s(lang="de")
    assert query_rows("SELECT settings->>'locale' FROM users WHERE id=81302") == [["de"]]

    for query <- ["utm_source=%GG", "utm_source=%FF", "locale=no&utm_source=x"] do
      assert AchievementPublicPage.call(build_conn("GET", path <> "?" <> query), []).status == 422
    end
  end

  defp change(attrs) do
    scope = Dawarich.Accounts.Scope.for_user(Dawarich.Accounts.get(81302), "en")

    Sharing.change(
      scope,
      %{type: :achievement, owner_id: 81302, key: "country_fr"},
      :update,
      attrs
    )
  end

  defp query_rows(sql), do: Dawarich.Repo.query!(sql, [], log: false).rows
end
