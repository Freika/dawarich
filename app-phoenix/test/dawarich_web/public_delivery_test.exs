defmodule DawarichWeb.PublicDeliveryTest do
  use Dawarich.DataCase, async: false
  import Plug.Conn
  import Phoenix.ConnTest
  alias Dawarich.Achievements.OgImage
  alias Dawarich.Test.RailsUser

  setup do
    user = RailsUser.insert!(%{id: 19020, email: "public-delivery@example.invalid"})
    uuid = Ecto.UUID.generate()

    rows(
      "INSERT INTO achievement_progresses(user_id,achievement_key,sharing_uuid,sharing_enabled,state,created_at,updated_at) VALUES($1,'country_de',$2,true,'{}',now(),now())",
      [user.id, uuid]
    )

    %{uuid: uuid, user: user}
  end

  for change <- [:revocation, :soft_deletion, :hard_deletion] do
    @tag review_delivery: true
    test "achievement PNG rendering refuses #{change} before delivery", %{uuid: uuid} do
      change = unquote(change)

      assert :not_found =
               OgImage.call(Dawarich.Repo, uuid,
                 render: fn _ ->
                   revoke(change)
                   "synthetic-png"
                 end
               )
    end

    @tag review_delivery: true
    test "warmed achievement PNG cache refuses #{change} before delivery", %{uuid: uuid} do
      assert {:ok, "synthetic-png"} =
               OgImage.call(Dawarich.Repo, uuid, render: fn _ -> "synthetic-png" end)

      assert :not_found =
               OgImage.call(Dawarich.Repo, uuid,
                 render: fn _ -> flunk("warm image must avoid rendering") end,
                 after_read: fn -> revoke(unquote(change)) end
               )
    end
  end

  @tag review_delivery: true
  test "public achievement image HTTP refuses revocation during rendering", %{uuid: uuid} do
    conn =
      build_conn("GET", "/shared/achievements/#{uuid}/og.png")
      |> DawarichWeb.AchievementPublicImage.call(
        render: fn _ ->
          revoke(:revocation)
          "synthetic-png"
        end
      )

    assert conn.status == 404
    assert conn.resp_body == ""
  end

  @tag review_delivery: true
  test "public achievement image HTTP refuses owner deletion after warmed cache retrieval", %{
    uuid: uuid
  } do
    assert {:ok, "synthetic-png"} =
             OgImage.call(Dawarich.Repo, uuid, render: fn _ -> "synthetic-png" end)

    conn =
      build_conn("GET", "/shared/achievements/#{uuid}/og.png")
      |> DawarichWeb.AchievementPublicImage.call(
        render: fn _ -> flunk("warm image must avoid rendering") end,
        after_read: fn -> revoke(:hard_deletion) end
      )

    assert conn.status == 404
    assert conn.resp_body == ""
  end

  @tag review_delivery: true
  test "native achievement HTTP document refuses revocation after HTML preparation", %{uuid: uuid} do
    conn =
      document_conn(uuid)
      |> put_private(:dawarich_before_delivery, fn -> revoke(:revocation) end)
      |> DawarichWeb.NativePublicPage.call(:achievement)

    assert conn.status == 302
    assert conn.resp_body == ""
  end

  @tag review_delivery: true
  test "routed achievement HTTP document refuses owner deletion after HTML preparation", %{
    uuid: uuid
  } do
    assert {:ok, page} = Dawarich.Sharing.Pages.achievement(uuid)

    conn =
      document_conn(uuid)
      |> assign(:achievement_public, {:ok, page})
      |> assign(:rails_session, %{})
      |> put_private(:dawarich_before_delivery, fn -> revoke(:soft_deletion) end)
      |> DawarichWeb.AchievementPublicPage.call([])

    assert conn.status == 302
    assert conn.resp_body == ""
  end

  defp document_conn(uuid) do
    build_conn("GET", "/shared/achievements/#{uuid}?embed=1")
    |> Map.merge(%{params: %{"embed" => "1"}, path_params: %{"uuid" => uuid}})
    |> assign(:locale, "en")
    |> assign(:base_url, "http://www.example.com")
    |> assign(:current_user, nil)
    |> assign(:self_hosted, true)
  end

  defp revoke(:revocation),
    do: rows("UPDATE achievement_progresses SET sharing_enabled=false WHERE user_id=19020")

  defp revoke(:soft_deletion), do: rows("UPDATE users SET deleted_at=now() WHERE id=19020")

  defp revoke(:hard_deletion) do
    rows("DELETE FROM achievement_progresses WHERE user_id=19020")
    rows("DELETE FROM users WHERE id=19020")
  end
end
