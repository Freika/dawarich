defmodule DawarichWeb.AchievementPublicQueryTest do
  use Dawarich.DataCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{AchievementPublicImage, AchievementPublicPage, Endpoint}

  @uuid "a12f0000-0000-4000-8000-000000081474"
  @path "/shared/achievements/" <> @uuid

  setup do
    previous = System.get_env("DAWARICH_RAILS")
    routes = Application.get_env(:dawarich, :rails_routes)
    System.put_env("DAWARICH_RAILS", "off")
    Application.put_env(:dawarich, :rails_routes, [])
    Dawarich.Test.AchievementSilhouettes.clear()

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")

      if is_nil(routes),
        do: Application.delete_env(:dawarich, :rails_routes),
        else: Application.put_env(:dawarich, :rails_routes, routes)

      Dawarich.Test.AchievementSilhouettes.clear()
    end)

    RailsUser.insert!(%{
      id: 81474,
      email: "achievement-query@example.invalid",
      settings: %{"locale" => "en", "timezone" => "UTC"}
    })

    rows(
      "INSERT INTO achievement_progresses(user_id,achievement_key,state,sharing_enabled,sharing_uuid,created_at,updated_at) VALUES(81474,'country_de','{}',true,$1,now(),now())",
      [@uuid]
    )

    :ok
  end

  for {name, query} <- [
        {"valueless unknown tracking key", "utm_source"},
        {"unclosed unknown bracket", "utm_source[=x"},
        {"unknown bracket with a trailing name", "utm_source[a]trailer=x"},
        {"depth 32 unknown value", "utm_source" <> String.duplicate("[a]", 32) <> "=x"}
      ] do
    @tag :fix2_ach_query
    test "public achievement routes ignore #{name}" do
      query = unquote(query)

      for endpoint <- [:card, :image], dispatch <- [:endpoint, :direct] do
        baseline = request("GET", endpoint, "", dispatch)
        assert baseline.status == 200
        result = request("GET", endpoint, query, dispatch)
        assert result.status == 200, "#{endpoint}/#{dispatch}: #{query}"

        if endpoint == :image do
          assert result.resp_body == baseline.resp_body
        else
          assert result.resp_body =~ "ach-card"
          assert result.query_params == %{}
          embedded = request("GET", endpoint, "embed=1&" <> query, dispatch)
          assert embedded.resp_body == request("GET", endpoint, "embed=1", dispatch).resp_body
        end

        assert stable_headers(result) == stable_headers(baseline)
        head = request("HEAD", endpoint, query, dispatch)
        assert head.status == 200 and head.resp_body == ""
        assert stable_headers(head) == stable_headers(result)

        for invalid <- ["utm_source=%GG", "utm_source=%FF", "%FF", "%GG"] do
          assert request("GET", endpoint, invalid, dispatch).status == 422
          assert request("HEAD", endpoint, invalid, dispatch).status == 422
        end
      end
    end
  end

  @tag :fix2_ach_query
  test "achievement unknown structures use Rails depth and type normalization" do
    for query <- [
          "utm_source" <> String.duplicate("[a]", 99) <> "=x",
          "utm_source&utm_source[a]=x",
          "utm_source[a]=x&utm_source=y",
          "utm_source[][a]=x&utm_source[][b]=y",
          "utm_source[][]=x&utm_source[][]=y",
          "utm_source[[]trailer=x",
          "[utm_source=x",
          "utm_source=x& release_probe=y",
          Enum.map_join(1..4097, "&", &"unknown#{&1}=x")
        ],
        endpoint <- [:card, :image] do
      assert request("GET", endpoint, query, :endpoint).status == 200, query
    end

    for query <- [
          "utm_source=x&utm_source[a]=y",
          "utm_source[]=x&utm_source[a]=y",
          "utm_source[a]=x&utm_source[]=y",
          "utm_source" <> String.duplicate("[a]", 100) <> "=x",
          "utm_source=" <> String.duplicate("x", 65_536),
          "locale",
          "locale[a]=en",
          "locale=en&locale=de",
          "embed",
          "embed[a]=1"
        ] do
      assert request("GET", :card, query, :endpoint).status == 422, query
    end

    refute DawarichWeb.Strangler.page_request?(
             build_conn("GET", "/shared/month/unknown?utm_source")
           )
  end

  defp stable_headers(conn), do: Enum.reject(conn.resp_headers, &(elem(&1, 0) == "set-cookie"))

  defp request(method, endpoint, query, dispatch) do
    suffix = if endpoint == :image, do: "/og.png", else: ""
    conn = build_conn(method, @path <> suffix <> if(query == "", do: "", else: "?" <> query))

    conn =
      put_req_header(conn, "accept", if(endpoint == :image, do: "image/png", else: "text/html"))

    case {endpoint, dispatch} do
      {_, :endpoint} -> Endpoint.call(conn, [])
      {:card, :direct} -> AchievementPublicPage.call(conn, [])
      {:image, :direct} -> AchievementPublicImage.call(conn, render: fn _ -> "probe-png" end)
    end
  end
end
