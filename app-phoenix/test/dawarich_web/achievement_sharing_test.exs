defmodule DawarichWeb.AchievementSharingTest do
  use Dawarich.IngestCase, async: true
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Plug.Conn
  alias Dawarich.{Repo, Sharing}
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint
  @uuid "a10c0000-0000-4000-8000-000000000001"
  setup do
    user =
      RailsUser.insert!(%{
        id: 44001,
        email: "sharing-native@example.invalid",
        settings: %{"locale" => "en"}
      })

    %{actor: user, scope: Dawarich.Accounts.Scope.for_user(user, "en")}
  end

  defp resource(key), do: %{type: :achievement, key: key, owner_id: 44001}

  defp open(referer) do
    RailsUser.signed_in(44001)
    |> RailsUser.connecting_as(44001)
    |> put_req_header("referer", referer)
    |> live("/achievements/country_de/sharing")
  end

  @tag :safe_back4
  @tag :safe_back4_signed
  test "native achievement sharing uses its resource return for every non-HTTP referer" do
    for scheme <- ~w(javascript JAVASCRIPT data vbscript file JaVaScRiPt DaTa),
        whitespace <- ["", " \t"] do
      {:ok, view, _} = open(whitespace <> scheme <> "://www.example.com/%0Aalert(1)")
      render_change(view, "report_sharing_update", %{"enabled" => "1"})
      assert has_element?(view, "a[href='/achievements/country_de']")

      assert rows(
               "SELECT sharing_enabled FROM achievement_progresses WHERE user_id=44001 AND achievement_key='country_de'"
             ) == [[true]]
    end
  end

  @tag :safe_back3
  test "native achievement resource returns ignore userinfo backslash and alternate-port referers" do
    for referer <- [
          "http://evil.example\\@www.example.com/offer",
          "//evil.example\\@www.example.com/offer",
          "http://user@www.example.com/offer",
          "/achievements/country_de?page=2#card",
          "https://www.example.com:8443/achievements/country_de?page=2"
        ] do
      {:ok, view, _} = open(referer)
      render_change(view, "report_sharing_update", %{"enabled" => "1"})
      assert has_element?(view, "a[href='/achievements/country_de']")
      refute has_element?(view, "a[href='http://evil.example\\@www.example.com/offer']")

      assert rows(
               "SELECT sharing_enabled FROM achievement_progresses WHERE user_id=44001 AND achievement_key='country_de'"
             ) == [[true]]
    end
  end

  test "native achievement fixture values preserve enablement uuid state and public links", c do
    fixtures =
      Path.expand("../fixtures/achievement_actions/responses.json", __DIR__)
      |> File.read!()
      |> Jason.decode!()

    for fixture <-
          Enum.filter(
            fixtures,
            &(&1["status"] in [200, 302] and is_binary(get_in(&1, ["before", "key"])))
          ) do
      key = fixture["before"]["key"]
      rows("DELETE FROM achievement_progresses WHERE user_id=44001")
      uuid = fixture["after"]["uuid"] || @uuid

      rows(
        "INSERT INTO achievement_progresses(user_id,achievement_key,state,sharing_enabled,sharing_uuid,created_at,updated_at) VALUES(44001,$1,$2,$3,$4,now(),now())",
        [key, fixture["before"]["state"], fixture["before"]["enabled"], uuid]
      )

      attrs = Map.take(fixture["params"], ["enabled"])
      assert {:ok, result} = Sharing.change(c.scope, resource(key), :update, attrs)
      assert result.uuid == uuid
      assert result.enabled == fixture["after"]["enabled"]

      assert [[result.enabled, uuid, fixture["before"]["state"]]] ==
               rows(
                 "SELECT sharing_enabled,sharing_uuid,state FROM achievement_progresses WHERE user_id=44001 AND achievement_key=$1",
                 [key]
               )

      assert {:ok, page} = Sharing.page(c.scope, resource(key))
      assert page == %{uuid: uuid, enabled: result.enabled}

      {:ok, view, _} =
        live(
          RailsUser.signed_in(44001) |> RailsUser.connecting_as(44001),
          "/achievements/#{key}/sharing"
        )

      if result.enabled,
        do:
          assert(has_element?(view, "a[data-public-share][href='/shared/achievements/#{uuid}']")),
        else: refute(has_element?(view, "[data-public-share]"))
    end
  end

  @tag a12f3b_case: "A02b"
  test "native achievement sharing remains terminal after response failure and refuses malformed input",
       c do
    {:ok, view, _} = open("/achievements")
    socket = :sys.get_state(view.pid).socket
    broken = %{socket | assigns: Map.delete(socket.assigns, :query_params)}

    assert_raise KeyError, fn ->
      DawarichWeb.SharingLive.Index.handle_event(
        "report_sharing_update",
        %{"enabled" => "1"},
        broken
      )
    end

    assert [[true, uuid]] =
             rows(
               "SELECT sharing_enabled,sharing_uuid FROM achievement_progresses WHERE user_id=44001"
             )

    assert is_binary(uuid)
    assert [[1]] = rows("SELECT count(*) FROM achievement_progresses WHERE user_id=44001")

    assert {:ok, %{enabled: false, uuid: ^uuid}} =
             Sharing.change(c.scope, resource("country_de"), :update, %{"enabled" => false})

    assert {:ok, %{enabled: true, uuid: ^uuid}} =
             Sharing.change(c.scope, resource("country_de"), :update, %{"enabled" => true})

    before =
      rows(
        "SELECT sharing_enabled,sharing_uuid,state FROM achievement_progresses WHERE user_id=44001"
      )

    assert {:error, :invalid_input} =
             Sharing.change(c.scope, resource("country_fr"), :update, %{"enabled" => nil})

    assert rows(
             "SELECT sharing_enabled,sharing_uuid,state FROM achievement_progresses WHERE user_id=44001"
           ) == before

    assert rows("SELECT settings FROM users WHERE id=44001") == [[%{"locale" => "en"}]]
  end

  defp rows(sql, args \\ []), do: Repo.query!(sql, args, log: false).rows
end
