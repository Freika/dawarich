defmodule DawarichWeb.A12f3bN09Test do
  use Dawarich.DataCase, async: false
  import Plug.Conn
  alias Dawarich.{Accounts, DemoData.Importer, Redis}
  alias Dawarich.Test.{DemoData, RailsUser}
  alias DawarichWeb.DemoDataActions

  setup do
    for spec <- Redis.cache_child_specs(), do: start_supervised!(spec)
    old = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if old, do: System.put_env("DAWARICH_RAILS", old), else: System.delete_env("DAWARICH_RAILS")
    end)

    for id <- [73901, 73902] do
      RailsUser.insert!(%{
        id: id,
        email: "demo-#{id}@test",
        settings: %{"timezone" => "Europe/Berlin"}
      })
    end

    :ok
  end

  @tag a12f3b_case: "N09a"
  test "demo DELETE preserves real data and publishes native recalculations" do
    user = Accounts.get(73901)
    opts = DemoData.fixtures()

    extra =
      put_in(
        opts[:points],
        ["features", Access.at(0), "properties", "timestamp"],
        1_779_926_400 - 40 * 86400
      )["features"]
      |> hd()

    opts =
      Keyword.update!(opts, :points, &Map.update!(&1, "features", fn rows -> rows ++ [extra] end))

    opts =
      Keyword.update!(
        opts,
        :derivatives,
        &Map.update!(&1, "stats_daily", fn rows ->
          rows ++ [%{"day_offset" => -40, "distance_meters" => 500}]
        end)
      )

    assert Importer.call(Repo, user, opts) == :created
    assert Importer.call(Repo, Accounts.get(73902), DemoData.fixtures()) == :created
    live = DemoData.real_point(73901, 1_774_735_230)
    foreign = rows("SELECT id FROM points WHERE user_id=73902 ORDER BY id")

    for key <- [
          "dawarich/user_73901_total_distance",
          "timeline_month_summary/73901/2026-03/Europe/Berlin/pro/v3",
          "insights/yearly_digest/73901/2026/synthetic"
        ] do
      assert {:ok, _} = Redis.cache_command(["SET", key, "synthetic"])
    end

    conn = DemoDataActions.call(DemoData.request(73901, :delete), :demo_data)
    assert conn.status == 302
    assert get_resp_header(conn, "location") == ["http://www.example.com/"]
    assert flash(conn, "notice") =~ "removed"
    assert rows("SELECT id FROM points WHERE user_id=73901") == [[live]]
    assert rows("SELECT id FROM points WHERE user_id=73902 ORDER BY id") == foreign

    for table <- ~w(imports tracks trips visits places tags) do
      assert rows("SELECT count(*) FROM #{table} WHERE user_id=73901 AND demo=true") == [[0]]
    end

    assert rows("SELECT year,month FROM stats WHERE user_id=73901") == [[2026, 3]]

    assert rows("SELECT command_type,payload FROM job_outbox ORDER BY event_id") == [
             [
               "stats.calculate_month",
               %{"user_id" => 73901, "year" => 2026, "month" => 3, "notify_on_failure" => false}
             ]
           ]

    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]

    Dawarich.Test.AfterCommit.drain(Repo)

    for key <- [
          "dawarich/user_73901_total_distance",
          "timeline_month_summary/73901/2026-03/Europe/Berlin/pro/v3",
          "insights/yearly_digest/73901/2026/synthetic"
        ] do
      assert Redis.cache_command(["GET", key]) == {:ok, nil}
    end

    empty =
      DemoDataActions.call(DemoData.request(73901, :post, %{"_method" => "delete"}), :demo_data)

    assert flash(empty, "notice") =~ "No demo"
    assert rows("SELECT count(*) FROM job_outbox") == [[1]]

    Repo.query!(
      "CREATE FUNCTION public.demo_delete_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'synthetic delete failure'; END $$",
      [],
      log: false
    )

    Repo.query!(
      "CREATE TRIGGER demo_delete_failure BEFORE DELETE ON imports FOR EACH ROW EXECUTE FUNCTION public.demo_delete_failure()",
      [],
      log: false
    )

    failed = DemoDataActions.call(DemoData.request(73902, :delete), :demo_data)
    assert flash(failed, "alert")
    assert rows("SELECT count(*) FROM imports WHERE user_id=73902 AND demo=true") == [[1]]
    assert rows("SELECT id FROM points WHERE user_id=73902 ORDER BY id") == foreign
  end

  @tag a12f3b_case: "N09b"
  test "demo cleanup cannot erase a shared real place or stat" do
    assert Importer.call(Repo, Accounts.get(73901), DemoData.fixtures()) == :created
    [[place]] = rows("SELECT id FROM places WHERE user_id=73901")
    [[tag]] = rows("SELECT id FROM tags WHERE user_id=73901")

    [[real_place]] =
      Repo.query!(
        "INSERT INTO places(user_id,name,latitude,longitude,demo,created_at,updated_at) VALUES (73901,'Real place',53,14,false,now(),now()) RETURNING id",
        [],
        log: false
      ).rows

    Repo.query!(
      "INSERT INTO taggings(tag_id,taggable_id,taggable_type,created_at,updated_at) VALUES ($1,$2,'Place',now(),now())",
      [tag, real_place],
      log: false
    )

    [[visit]] =
      Repo.query!(
        "INSERT INTO visits(user_id,place_id,name,started_at,ended_at,duration,demo,created_at,updated_at) VALUES (73901,$1,'Real visit',now(),now(),0,false,now(),now()) RETURNING id",
        [place],
        log: false
      ).rows

    live = DemoData.real_point(73901, 1_774_735_230)

    conn =
      DemoDataActions.call(DemoData.request(73901, :post, %{"_method" => "delete"}), :demo_data)

    assert conn.status == 302

    assert rows("SELECT id FROM places WHERE user_id=73901 ORDER BY id") ==
             Enum.sort([[place], [real_place]])

    assert rows("SELECT id FROM visits WHERE user_id=73901") == [[visit]]
    assert rows("SELECT id FROM tags WHERE user_id=73901") == [[tag]]

    assert rows("SELECT tag_id,taggable_id FROM taggings WHERE tag_id=$1 ORDER BY taggable_id", [
             tag
           ]) == Enum.sort([[tag, place], [tag, real_place]])

    assert rows("SELECT id FROM points WHERE user_id=73901") == [[live]]
    assert rows("SELECT year,month,distance FROM stats WHERE user_id=73901") == [[2026, 3, 1000]]

    assert rows("SELECT payload FROM job_outbox") == [
             [%{"user_id" => 73901, "year" => 2026, "month" => 3, "notify_on_failure" => false}]
           ]
  end

  defp flash(conn, key), do: conn.private.dawarich_rails_session_changes["flash"]["flashes"][key]
end
