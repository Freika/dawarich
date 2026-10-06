defmodule DawarichWeb.A12f3bS06Test do
  use Dawarich.IngestCase, async: false
  alias Dawarich.Test.A12f3bShareCase, as: S
  alias Dawarich.ShareManagement.TimelineMutations
  alias DawarichWeb.TimelineShareActions

  setup do
    %{actor: S.seed!()}
  end

  @tag a12f3b_case: "S06a"
  test "timeline share six legacy actions preserve active range and grants", %{actor: actor} do
    form = S.request(actor, "timeline", :new) |> TimelineShareActions.call(:new)
    assert form.status == 200
    head = S.request(actor, "timeline", :new) |> Map.put(:method, "HEAD")
    assert TimelineShareActions.native?(head, head.path_params)
    assert (head |> Plug.Head.call([]) |> TimelineShareActions.call(:new)).status == 200
    assert form.resp_body =~ "/share_links/timeline"

    Repo.query!(
      "INSERT INTO shared_links(id,user_id,resource_type,name,settings,created_at,updated_at) VALUES($1::text::uuid,98102,2,'Foreign timeline',$2,$3,$3)",
      [
        S.id(0),
        %{"start_date" => "2026-09-01", "end_date" => "2026-09-07"},
        DateTime.to_naive(S.now())
      ]
    )

    assert {:ok, %{share: %{user_id: owner}}} = S.read(actor, "timeline")
    assert owner == actor.id

    for action <- [:create, :regenerate, :regenerate_phrase, :revoke, :create, :destroy] do
      params = if action == :create, do: S.params("timeline"), else: %{}
      response = S.request(actor, "timeline", action, params) |> TimelineShareActions.call(action)
      assert response.status == 302

      assert Repo.query!("SELECT revoked_at FROM shared_links WHERE id=$1::text::uuid", [S.id(0)]).rows ==
               [[nil]]
    end

    assert {:ok, %{share: nil}} = S.read(actor, "timeline")
    assert {:missing, "/map/v2"} = TimelineMutations.run(actor, :revoke, %{}, "en", now: S.now())
  end

  @tag a12f3b_case: "S06b"
  test "timeline malformed range preserves existing grant", %{actor: actor} do
    before = S.rows()

    assert {:invalid, %{errors: [{:settings, _}]}} =
             TimelineMutations.run(
               actor,
               :create,
               S.params("timeline", %{"end_date" => "2026-08-01"}),
               "en",
               now: S.now()
             )

    assert S.rows() == before

    assert :rails =
             TimelineMutations.run(
               actor,
               :create,
               S.params("timeline", %{"start_date" => %{"nested" => "2026-09-01"}}),
               "en",
               now: S.now()
             )

    assert S.rows() == before

    Repo.query!(
      "ALTER TABLE shared_links ADD CONSTRAINT a12f3b_timeline_sql CHECK(name <> 'Rejected SQL') NOT VALID"
    )

    assert_raise Postgrex.Error, fn ->
      TimelineMutations.run(
        actor,
        :create,
        S.params("timeline", %{"name" => "Rejected SQL"}),
        "en",
        now: S.now()
      )
    end

    assert S.rows() == before
    Repo.query!("ALTER TABLE shared_links DROP CONSTRAINT a12f3b_timeline_sql")
  end
end
