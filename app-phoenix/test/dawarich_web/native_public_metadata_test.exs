defmodule DawarichWeb.NativePublicMetadataTest do
  use Dawarich.DataCase, async: false
  import Plug.Conn
  import Phoenix.ConnTest
  alias Dawarich.Test.RailsUser

  setup do
    RailsUser.insert!(%{
      id: 19001,
      email: "native-public-card@example.invalid",
      api_key: "synthetic-owner-secret",
      settings: %{"locale" => "de", "timezone" => "Europe/Berlin"}
    })

    uuid = Ecto.UUID.generate()

    rows(
      "INSERT INTO achievement_progresses(user_id,achievement_key,sharing_uuid,sharing_enabled,state,created_at,updated_at) VALUES(19001,'country_de',$1,true,'{}',now(),now())",
      [uuid]
    )

    %{uuid: uuid}
  end

  test "native public achievement documents retain metadata and HEAD embed headers", %{uuid: uuid} do
    for embed <- [false, true] do
      conn = request(uuid, "GET", embed)
      assert conn.status == 200
      assert conn.resp_body =~ "og:image"
      assert conn.resp_body =~ "/#{uuid}/og.png"
      assert conn.resp_body =~ "twitter:card"
      assert conn.resp_body =~ ~s(lang="de")
      assert get_resp_header(conn, "content-security-policy") == ["frame-ancestors *"]
      assert get_resp_header(conn, "x-frame-options") == []
      assert get_resp_header(conn, "cache-control") == ["max-age=0, private, must-revalidate"]
      refute conn.resp_body =~ "importmap"
      refute conn.resp_body =~ "data-controller="
      refute conn.resp_body =~ "synthetic-owner-secret"
      if embed, do: refute(conn.resp_body =~ "<header")
      head = request(uuid, "HEAD", embed)
      assert head.status == 200
      assert head.resp_body == ""

      assert get_resp_header(head, "content-security-policy") ==
               get_resp_header(conn, "content-security-policy")
    end

    rows("UPDATE achievement_progresses SET sharing_enabled=false WHERE user_id=19001")
    assert request(uuid, "GET", false).status == 302
  end

  defp request(uuid, method, embed) do
    conn = build_conn(method, "/shared/achievements/" <> uuid)

    conn = %{
      conn
      | params: %{"embed" => if(embed, do: "1", else: "0")},
        path_params: %{"uuid" => uuid}
    }

    conn =
      conn
      |> assign(:locale, "en")
      |> assign(:base_url, "http://www.example.com")
      |> assign(:current_user, nil)
      |> assign(:self_hosted, true)
      |> assign(:now, DateTime.utc_now())

    apply(DawarichWeb.NativePublicPage, :call, [conn, :achievement])
  end
end
