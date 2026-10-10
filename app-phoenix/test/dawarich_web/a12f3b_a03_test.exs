defmodule DawarichWeb.A12f3bA03Test do
  use Dawarich.DataCase, async: false
  import Plug.Conn
  import Phoenix.ConnTest
  alias Dawarich.Test.RailsUser

  defmodule Routes do
    use Phoenix.Router
    import DawarichWeb.AchievementImageRoutes
    achievement_image_routes()
  end

  @uuid "a12f0000-0000-4000-8000-000000081303"

  setup do
    Dawarich.Test.AchievementSilhouettes.clear()
    on_exit(&Dawarich.Test.AchievementSilhouettes.clear/0)

    RailsUser.insert!(%{
      id: 81303,
      email: "achievement-png@example.invalid",
      settings: %{"locale" => "en", "timezone" => "UTC"}
    })

    rows(
      "INSERT INTO achievement_progresses(user_id,achievement_key,state,sharing_enabled,sharing_uuid,created_at,updated_at) VALUES(81303,'country_de','{}',true,$1,now(),now())",
      [@uuid]
    )

    rows(
      "INSERT INTO achievement_progresses(user_id,achievement_key,state,created_at,updated_at) VALUES(81303,'exploration',$1,now(),now())",
      [
        %{
          "earned" =>
            Map.new(
              Dawarich.Achievements.Registry.find("country_de").region_codes,
              &{&1, "2026-10-04T22:30:00Z"}
            )
        }
      ]
    )

    :ok
  end

  @tag a12f3b_case: "A03a"
  test "achievement OG image matches source dimensions headers and state" do
    first = image()
    assert first.status == 200

    assert <<137, 80, 78, 71, 13, 10, 26, 10, _::binary-size(8), 1200::32, 630::32, _::binary>> =
             first.resp_body

    assert get_resp_header(first, "content-type") == ["image/png"]
    assert get_resp_header(first, "content-disposition") == ["inline"]
    assert get_resp_header(first, "cache-control") == ["private, no-store"]
    assert get_resp_header(first, "x-frame-options") == ["SAMEORIGIN"]
    assert image().resp_body == first.resp_body
    head = image("HEAD")
    assert head.status == 200 and head.resp_body == ""
    assert head.resp_headers == first.resp_headers

    rows(
      "UPDATE users SET settings=settings||'{\"timezone\":\"Pacific/Chatham\"}'::jsonb WHERE id=81303"
    )

    changed_zone = image()
    refute changed_zone.resp_body == first.resp_body
    rows("UPDATE users SET settings=settings||'{\"locale\":\"de\"}'::jsonb WHERE id=81303")
    changed_locale = image()
    refute changed_locale.resp_body == changed_zone.resp_body

    rows(
      "UPDATE achievement_progresses SET state='{\"earned\":{}}' WHERE user_id=81303 AND achievement_key='exploration'"
    )

    refute image().resp_body == changed_locale.resp_body
    assert image("GET", "unknown").status == 404

    rows("UPDATE achievement_progresses SET achievement_key='unknown' WHERE sharing_uuid=$1", [
      @uuid
    ])

    assert image().status == 404
  end

  @tag a12f3b_case: "A03b"
  test "achievement disabled share denies a previously cached PNG" do
    assert image().status == 200
    rows("UPDATE achievement_progresses SET sharing_enabled=false WHERE sharing_uuid=$1", [@uuid])
    denied = image()
    assert denied.status == 404 and denied.resp_body == ""
    assert get_resp_header(denied, "cache-control") == ["private, no-store"]
    assert image("HEAD").status == 404
    rows("UPDATE achievement_progresses SET sharing_enabled=true WHERE sharing_uuid=$1", [@uuid])
    assert image().status == 200
    rows("UPDATE users SET deleted_at=now() WHERE id=81303")
    assert image().status == 404
  end

  @tag :fix_ach_image_params
  test "achievement PNG ignores crawler query keys without changing admission or responses" do
    baseline = image()

    for query <- [
          "utm_source=x&release_probe=y",
          "%75tm_source=x",
          "utm_source=x&utm_source=y",
          "utm_source[a]=x&embed=1",
          "utm_source",
          "locale=de&utm_source=x"
        ] do
      actual = image("GET", @uuid, query)
      assert actual.status == 200, query
      assert actual.resp_body == baseline.resp_body
      assert actual.resp_headers == baseline.resp_headers
      head = image("HEAD", @uuid, query)
      assert head.status == 200 and head.resp_body == ""
      assert head.resp_headers == baseline.resp_headers
      missing = image("GET", "unknown", query)
      assert missing.status == 404 and missing.resp_body == ""
      assert get_resp_header(missing, "cache-control") == ["private, no-store"]
    end

    for query <- [
          "utm_source=%GG",
          "utm_source=%",
          "%GG=x",
          "utm_source=%FF",
          "%FF=x",
          "utm_source=x&utm_source[a]=y",
          "utm_source" <> String.duplicate("[a]", 100) <> "=x",
          "utm_source=" <> String.duplicate("x", 65_536),
          "locale=en&locale=de"
        ] do
      assert image("GET", @uuid, query).status == 422
    end

    duplicate =
      build_conn("GET", "/shared/achievements/#{@uuid}/og.png?utm_source=x")
      |> Map.put(:req_headers, [{"accept", "image/png"}, {"accept", "image/png"}])
      |> DawarichWeb.AchievementPublicImage.call([])

    assert duplicate.status == 422
    rows("UPDATE achievement_progresses SET sharing_enabled=false WHERE sharing_uuid=$1", [@uuid])
    assert image("GET", @uuid, "utm_source=x").status == 404
  end

  defp image(method \\ "GET", uuid \\ @uuid, query \\ "") do
    build_conn(
      method,
      "/shared/achievements/#{uuid}/og.png" <> if(query == "", do: "", else: "?" <> query)
    )
    |> put_req_header("accept", "image/png")
    |> put_private(:dawarich_method, method)
    |> Plug.Head.call([])
    |> Routes.call(Routes.init([]))
  end
end
