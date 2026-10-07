defmodule DawarichWeb.A12f3bN08Test do
  use Dawarich.DataCase, async: false
  import Plug.Conn
  alias Dawarich.{Accounts, DemoData.Importer}
  alias Dawarich.Test.{DemoData, RailsUser}
  alias DawarichWeb.DemoDataActions

  setup do
    RailsUser.insert!(%{
      id: 73801,
      email: "demo-n08@test",
      settings: %{"timezone" => "Europe/Berlin"}
    })

    RailsUser.insert!(%{id: 73802, email: "demo-n08-foreign@test"})
    :ok
  end

  @tag a12f3b_case: "N08a"
  test "demo import seeds scoped derivatives and source landing URL" do
    Repo.query!(
      "INSERT INTO tags(user_id,name,icon,color,created_at,updated_at) VALUES (73801,'home','R','#ffffff',now(),now())",
      [],
      log: false
    )

    conn = DemoDataActions.call(DemoData.request(73801, :post), :demo_data, DemoData.fixtures())
    assert conn.status == 302
    [url] = get_resp_header(conn, "location")
    query = URI.decode_query(URI.parse(url).query)
    assert URI.parse(url).path == "/map/v2"

    assert query == %{
             "panel" => "timeline",
             "date" => "2026-03-29",
             "start_at" => "2026-03-29T00:00:00+01:00",
             "end_at" => "2026-03-29T23:59:59+02:00"
           }

    assert flash(conn, "notice") =~ "Demo"

    assert rows("SELECT user_id,demo,name,geodata FROM places") == [
             [73801, true, "Home", %{"city" => "Berlin"}]
           ]

    assert rows("SELECT demo,icon,color FROM tags WHERE user_id=73801") == [
             [false, "R", "#ffffff"]
           ]

    assert rows("SELECT count(*) FROM taggings") == [[1]]
    assert rows("SELECT user_id,demo,duration,status FROM visits") == [[73801, true, 10, 0]]
    assert rows("SELECT count(*) FROM place_visits") == [[1]]
    assert rows("SELECT user_id,demo,distance FROM trips") == [[73801, true, 1000]]

    assert rows("SELECT body FROM action_text_rich_texts WHERE record_type='Trip'") == [
             ["Synthetic trip"]
           ]

    assert rows("SELECT year,month,distance,daily_distance FROM stats") == [
             [2026, 3, 1000, [[29, 1000]]]
           ]

    [[toponyms]] = rows("SELECT toponyms FROM stats")
    assert Enum.map(toponyms, & &1["country"]) == ["Germany", "Czech Republic"]

    assert DemoDataActions.call(DemoData.request(73801, :post), :demo_data, DemoData.fixtures()).status ==
             302

    assert rows("SELECT count(*) FROM visits") == [[1]]

    for conn <- [
          assign(DemoData.request(73801, :post), :current_user, nil),
          assign(DemoData.request(73801, :post), :api_params, %{}),
          put_req_header(DemoData.request(73801, :post), "origin", "https://foreign.test")
        ] do
      assert DemoDataActions.call(conn, :demo_data).status in [302, 422]
    end

    assert Importer.call(Repo, Accounts.get(73802)) == :created
    assert rows("SELECT count(*) FROM points WHERE user_id=73802") == [[17988]]
    assert rows("SELECT count(*) FROM tracks WHERE user_id=73802 AND demo=true") == [[118]]
    assert rows("SELECT count(*) FROM visits WHERE user_id=73802 AND demo=true") == [[148]]
  end

  @tag a12f3b_case: "N08b"
  test "demo derivative failure does not leave a successful marker" do
    DemoData.fail_visits()
    conn = DemoDataActions.call(DemoData.request(73801, :post), :demo_data, DemoData.fixtures())
    assert conn.status == 302
    assert get_resp_header(conn, "location") == ["http://www.example.com/"]
    assert flash(conn, "alert")
    refute flash(conn, "notice")

    for table <- ~w(imports points tags places visits trips stats tracks) do
      assert rows("SELECT count(*) FROM #{table} WHERE user_id=73801") == [[0]]
    end
  end

  defp flash(conn, key), do: conn.private.dawarich_rails_session_changes["flash"]["flashes"][key]
end
