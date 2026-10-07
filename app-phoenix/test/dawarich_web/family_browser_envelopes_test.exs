defmodule DawarichWeb.FamilyBrowserEnvelopesTest do
  use Dawarich.JobsCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.RailsCsrf
  @endpoint DawarichWeb.Endpoint
  @accept "text/vnd.turbo-stream.html, text/html, application/xhtml+xml"

  setup do
    context = Dawarich.Test.FamilyForms.seed()
    saved = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if saved,
        do: System.put_env("DAWARICH_RAILS", saved),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    context
  end

  @tag :sa_g44_families_leave
  test "confirmed browser leave removes one membership and redirects", c do
    response = browser(c.member, "/family/members/92002?_method=delete", %{"_method" => "delete"})
    assert response.status == 302
    assert get_resp_header(response, "location") == ["http://www.example.com/family/new"]
    assert records("SELECT count(*) FROM family_memberships WHERE id=92002") == [[0]]
  end

  @tag :sa_g44_families_remove
  test "confirmed browser remove preserves the owner and removes the member", c do
    response = browser(c.owner, "/family/members/92002?_method=delete", %{"_method" => "delete"})
    assert response.status == 302
    assert get_resp_header(response, "location") == ["http://www.example.com/family"]
    assert records("SELECT id FROM family_memberships WHERE family_id=91001") == [[92001]]
  end

  @tag :sa_g44_families_accept
  test "browser invitation acceptance joins once and permits leaving", c do
    response =
      browser(c.outsider, "/family/memberships?token=a9fpl-pending", %{"_method" => "post"})

    assert response.status == 302
    assert get_resp_header(response, "location") == ["http://www.example.com/family"]
    assert [[id]] = records("SELECT id FROM family_memberships WHERE user_id=90103")

    response =
      browser(Accounts.get(c.outsider.id), "/family/members/#{id}?_method=delete", %{
        "_method" => "delete"
      })

    assert response.status == 302
    assert records("SELECT count(*) FROM family_memberships WHERE user_id=90103") == [[0]]
  end

  @tag :sa_g44_families_delete
  test "browser family deletion refuses members until the owner removes them", c do
    response = browser(c.owner, "/family?_method=delete", %{"_method" => "delete"})
    assert response.status == 302
    assert get_resp_header(response, "location") == ["http://www.example.com/family"]
    assert records("SELECT count(*) FROM families WHERE id=91001") == [[1]]

    assert browser(c.owner, "/family/members/92002?_method=delete", %{"_method" => "delete"}).status ==
             302

    assert browser(c.owner, "/family?_method=delete", %{"_method" => "delete"}).status == 302
    assert records("SELECT count(*) FROM families WHERE id=91001") == [[0]]
  end

  @tag :sa_g44_families_history
  test "browser Turbo sharing form persists live location and history consent", c do
    assert sharing(c.owner, true).status == 200
    assert sharing(c.owner, true, %{"duration" => "1h"}).status == 200
    assert sharing(c.owner, true, %{"duration" => "1h", "share_history" => "true"}).status == 200

    response =
      sharing(c.owner, true, %{
        "duration" => "1h",
        "share_history" => "true",
        "history_window" => "30d"
      })

    assert response.status == 200

    assert get_resp_header(response, "content-type") == [
             "text/vnd.turbo-stream.html; charset=utf-8"
           ]

    assert response.resp_body =~ ~s(target="location-sharing-90101")
    settings = Accounts.settings(c.owner.id)["family"]["location_sharing"]
    assert settings["enabled"]
    assert settings["share_history"]
    assert settings["history_window"] == "30d"
  end

  @tag :sa_g44_families_map
  test "browser family map includes only consenting members and removes revoked consent", c do
    Repo.query!("UPDATE users SET settings=settings-'family' WHERE id IN (90101,90102)")

    Repo.query!(
      "INSERT INTO points(user_id,timestamp,lonlat,created_at,updated_at) VALUES($1,1791021600,ST_SetSRID(ST_MakePoint(13.406,52.521),4326),now(),now())",
      [c.member.id]
    )

    assert locations(c.owner) == []
    assert sharing(c.member, true).status == 200
    assert [%{"user_id" => 90102}] = locations(c.owner)
    assert sharing(c.member, false).status == 200
    assert locations(c.owner) == []
  end

  defp sharing(user, enabled, attrs \\ %{}) do
    params =
      Map.merge(
        %{
          "_method" => "patch",
          "enabled" => to_string(enabled),
          "duration" => "permanent",
          "share_history" => "false",
          "history_window" => "7d"
        },
        attrs
      )

    browser(user, "/family/location_sharing", params, [
      {"turbo-frame", "location-sharing-#{user.id}"}
    ])
  end

  defp browser(user, path, params, headers \\ []) do
    session = RailsUser.session(user.id)
    token = RailsCsrf.masked_token(session)
    delete? = params["_method"] == "delete"
    navigation? = params["_method"] == "post"

    body =
      params
      |> then(fn params ->
        if delete?, do: params, else: Map.put(params, "authenticity_token", token)
      end)
      |> Plug.Conn.Query.encode()

    conn =
      build_conn()
      |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
      |> put_req_header(
        "content-type",
        if(navigation?,
          do: "application/x-www-form-urlencoded",
          else: "application/x-www-form-urlencoded;charset=UTF-8"
        )
      )
      |> put_req_header("content-length", to_string(byte_size(body)))
      |> put_req_header(
        "accept",
        if(params["_method"] == "post",
          do:
            "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
          else: @accept
        )
      )
      |> then(fn conn ->
        if navigation?, do: conn, else: put_req_header(conn, "x-csrf-token", token)
      end)
      |> put_req_header("origin", "http://www.example.com")
      |> assign(:now, ~U[2026-10-03 10:00:00Z])

    conn = Enum.reduce(headers, conn, fn {k, v}, conn -> put_req_header(conn, k, v) end)
    post(conn, path, body)
  end

  defp locations(user) do
    RailsUser.signed_in(user.id)
    |> assign(:now, ~U[2026-10-03 10:00:00Z])
    |> get("/family/locations.json")
    |> json_response(200)
  end

  defp records(sql), do: Repo.query!(sql).rows
end
