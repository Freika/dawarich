defmodule DawarichWeb.A12f3bS01Test do
  use Dawarich.IngestCase, async: false
  import Plug.Conn
  import Plug.Test
  alias DawarichWeb.{SharedLinkCookie, SharedLinkPage}
  alias Dawarich.{RailsCookies, RailsSecret, SharedLinks}
  @id "a12f3000-0000-4000-8000-000000000001"

  setup do
    user = user!(%{settings: %{"timezone" => "UTC"}})

    Repo.query!(
      "INSERT INTO shared_links(id,user_id,resource_type,name,magic_phrase,settings,created_at,updated_at) VALUES($1::text::uuid,$2,3,'Synthetic share','synthetic-phrase',$3,now(),now())",
      [@id, user, %{"audience" => "family", "family_id" => -1}]
    )

    :ok
  end

  @tag a12f3b_case: "S01a"
  test "public links preserve phrase cookie and expiry refusals" do
    now = DateTime.utc_now()
    link = SharedLinks.active(@id, now)

    for at <- [DateTime.add(now, -1), now] do
      value =
        RailsCookies.encrypt(
          SharedLinkCookie.unlock_token(@id, link.magic_phrase),
          "shared_link_#{@id}",
          RailsSecret.fetch(),
          at
        )

      refute SharedLinkCookie.unlocked?(
               conn(:get, "/s/#{@id}") |> put_req_cookie("shared_link_#{@id}", value),
               link,
               now
             )
    end

    for action <- [:show, :unlock] do
      response = request(action) |> SharedLinkPage.call(action)
      assert response.status == 404
      assert get_resp_header(response, "x-robots-tag") == ["noindex, nofollow"]
      refute Map.has_key?(response.resp_cookies, "shared_link_#{@id}")
    end

    assert Repo.query!("SELECT view_count FROM shared_links WHERE id=$1::text::uuid", [@id]).rows ==
             [[0]]
  end

  @tag a12f3b_case: "S01b"
  test "public link owner retirement removes access immediately" do
    now = DateTime.utc_now()
    assert SharedLinks.active(@id, now)
    Repo.query!("UPDATE shared_links SET revoked_at=now() WHERE id=$1::text::uuid", [@id])
    refute SharedLinks.active(@id, now)
    Repo.query!("DELETE FROM shared_links WHERE id=$1::text::uuid", [@id])
    refute SharedLinks.active(@id, now)
  end

  defp request(action) do
    conn(if(action == :show, do: :get, else: :post), "/s/#{@id}")
    |> Map.put(:path_params, %{"id" => @id})
    |> assign(:current_user, nil)
    |> assign(:locale, "en")
    |> assign(:rails_session, %{})
    |> assign(:rails_csrf_token, "synthetic")
    |> assign(:base_url, "http://www.example.com")
    |> assign(:api_params, %{"phrase" => "synthetic-phrase"})
  end
end
