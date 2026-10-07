defmodule DawarichWeb.A12f3bA02Test do
  use Dawarich.DataCase, async: false
  import Plug.Conn
  import Phoenix.ConnTest
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{AchievementPublicPage, RailsCsrf}
  alias DawarichWeb.AchievementActions.Sharing

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
  test "achievement sharing and public embeds close remaining gates" do
    session = RailsUser.session(81302)
    path = "/achievements/country_fr/toggle_sharing"
    result = Sharing.call(sharing("PATCH", path, session, %{"enabled" => true}), [])
    assert result.status == 200
    uuid = Jason.decode!(result.resp_body)["uuid"]
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
    assert rows("SELECT settings->>'locale' FROM users WHERE id=81302") == [["de"]]
    assert AchievementPublicPage.call(build_conn("HEAD", url <> "?embed=1"), []).resp_body == ""

    assert Sharing.call(
             sharing("POST", path, session, %{"_method" => "patch", "enabled" => "false"}),
             []
           ).status == 302

    assert AchievementPublicPage.call(build_conn("GET", url <> "?embed=1"), []).status == 302
    again = Sharing.call(sharing("PATCH", path, session, %{"enabled" => true}), [])
    assert Jason.decode!(again.resp_body)["uuid"] == uuid
    assert AchievementPublicPage.call(build_conn("GET", url <> "?embed=1"), []).status == 200

    assert AchievementPublicPage.call(build_conn("GET", "/shared/achievements/unknown"), []).status ==
             302

    assert Sharing.call(sharing("PATCH", path, session, %{"enabled" => nil}), []).status == 422
    assert rows("SELECT count(*) FROM achievement_progresses WHERE user_id=81302") == [[1]]
  end

  @tag :fix_ach_image_params
  test "public achievement cards ignore crawler query keys and preserve locale and embeds" do
    result =
      Sharing.call(
        sharing("PATCH", "/achievements/country_fr/toggle_sharing", RailsUser.session(81302), %{
          "enabled" => true
        }),
        []
      )

    uuid = Jason.decode!(result.resp_body)["uuid"]
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
    assert rows("SELECT settings->>'locale' FROM users WHERE id=81302") == [["de"]]

    for query <- ["utm_source=%GG", "utm_source=%FF", "locale=no&utm_source=x"] do
      assert AchievementPublicPage.call(build_conn("GET", path <> "?" <> query), []).status == 422
    end
  end

  defp sharing(method, path, session, params) do
    form = method == "POST"
    token = RailsCsrf.masked_form_token(session, path, "PATCH")

    body =
      if form,
        do: URI.encode_query(Map.put(params, "authenticity_token", token)),
        else: Jason.encode!(params)

    conn =
      build_conn(method, path, body)
      |> put_req_header("accept", if(form, do: "text/html", else: "application/json"))
      |> put_req_header(
        "content-type",
        if(form, do: "application/x-www-form-urlencoded", else: "application/json")
      )
      |> put_req_header("content-length", to_string(byte_size(body)))
      |> Plug.Test.put_req_cookie("_dawarich_session", RailsUser.cookie(session))

    if form, do: conn, else: put_req_header(conn, "x-csrf-token", token)
  end
end
