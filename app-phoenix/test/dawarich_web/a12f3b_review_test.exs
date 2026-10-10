defmodule DawarichWeb.A12f3bReviewTest do
  use Dawarich.IngestCase, async: false
  import Plug.Conn
  import Plug.Test, only: [put_req_cookie: 3]
  alias Dawarich.Test.{A12f3bShareCase, RailsUser}
  alias A12f3bShareCase, as: S
  alias Dawarich.{Sharing, Repo}
  alias Dawarich.ShareManagement.{Params, Read}
  alias DawarichWeb.Locale
  setup do: %{actor: S.seed!()}

  defp change(actor, type, id, action, attrs, locale \\ "en"),
    do:
      Sharing.change(
        Dawarich.Accounts.Scope.for_user(actor, locale),
        Map.merge(%{type: type, owner_id: actor.id}, if(id, do: %{id: id}, else: %{})),
        action,
        attrs,
        now: S.now()
      )

  @tag review_case: "F1"
  test "native F1 explicit sharing actions preserve protected grants without method guessing", %{
    actor: actor
  } do
    for {type, id, key} <- [
          {:track, 99103, S.id(7)},
          {:timeline, nil, S.id(5)},
          {:live, nil, S.id(1)},
          {:trip, 99101, S.id(6)}
        ] do
      Repo.query!("UPDATE shared_links SET magic_phrase='protected' WHERE id=$1::text::uuid", [
        key
      ])

      assert {:ok, _} = change(actor, type, id, :destroy, %{})
      assert Repo.query!("SELECT id FROM shared_links WHERE id=$1::text::uuid", [key]).rows == []

      assert {:ok, %{share: share}} =
               change(actor, type, id, :create, S.params(Atom.to_string(type)))

      assert {:ok, _} = change(actor, type, id, :revoke, %{})
      refute Dawarich.SharedLinks.active(share.id, S.now())
      before = S.rows()
      assert {:error, :invalid_input} = change(actor, type, id, :patch, %{})
      assert S.rows() == before

      assert {:ok, %{share: created}} =
               change(actor, type, id, :create, S.params(Atom.to_string(type)))

      assert {:ok, %{share: %{magic_phrase: "synthetic-phrase"}}} =
               Read.owned(actor, created.id)
    end

    assert {:ok, %{share: share}} = change(actor, :track, 99103, :create, S.params("track"))
    assert {:ok, _} = change(actor, :shared, share.id, :revoke, %{})
    refute Dawarich.SharedLinks.active(share.id, S.now())
    assert commands() == []
  end

  @tag review_case: "F2"
  test "native F2 invalid live creation reports validation without changing its active grant", %{
    actor: actor
  } do
    before = S.rows()

    for params <- [
          S.params("track", %{"magic_phrase" => String.duplicate("x", 256)}),
          Map.put(
            S.params("track", %{"magic_phrase" => String.duplicate("x", 256)}),
            "hub",
            "false"
          )
        ] do
      assert {:error, %{errors: [_ | _]}} = change(actor, :live, nil, :create, params)
      assert S.rows() == before
      assert Dawarich.SharedLinks.active(S.id(1), S.now())
    end

    assert commands() == []
  end

  @tag review_case: "F3"
  test "native F3 flexible timeline dates refuse before validation or display effects", %{
    actor: actor
  } do
    before = S.rows()

    for {first, last} <- [
          {"September", "October"},
          {"Sep 1, 2026", "October 2, 2026"},
          {"2026/09/01", "2026/10/01"}
        ] do
      params = S.params("timeline", %{"start_date" => first, "end_date" => last})
      assert Params.create(actor, "timeline", nil, params, "en") == :rails
      assert {:error, :invalid_input} = change(actor, :timeline, nil, :create, params)
      assert S.rows() == before
    end
  end

  @tag review_case: "F3"
  test "native F3 existing month-name timeline refuses unsupported display without changing stored settings",
       %{actor: actor} do
    settings = %{"start_date" => "September", "end_date" => "October"}

    Repo.query!("UPDATE shared_links SET settings=$2 WHERE id=$1::text::uuid", [S.id(5), settings])

    before = S.rows()

    assert {:error, :invalid_input} =
             Sharing.page(
               Dawarich.Accounts.Scope.for_user(actor, "en"),
               %{type: :timeline, owner_id: actor.id},
               %{},
               now: S.now()
             )

    assert Read.timeline(actor, %{}, S.now()) == :rails
    assert S.rows() == before

    assert Repo.query!("SELECT settings FROM shared_links WHERE id=$1::text::uuid", [S.id(5)]).rows ==
             [[settings]]
  end

  @tag review_case: "F4"
  test "native F4 track labels and persisted names use resolved preference and session locale", %{
    actor: actor
  } do
    expected = "Stationär · 3. Okt 2026 · 2 km"

    for {preference, session_locale} <- [{" de ", "en"}, {nil, "de"}] do
      settings =
        actor.settings |> Map.put("locale", preference) |> Map.put("timezone", "Europe/Berlin")

      Repo.query!("UPDATE users SET settings=$2 WHERE id=$1", [actor.id, settings])
      user = %{actor | settings: settings}
      session = RailsUser.session(actor.id, %{"locale" => session_locale})
      assert Locale.resolve(nil, user, session) == "de"
      Repo.query!("DELETE FROM shared_links WHERE user_id=$1 AND resource_type=1", [actor.id])

      assert {:ok, %{trip: %{name: ^expected}}} =
               Sharing.page(
                 Dawarich.Accounts.Scope.for_user(user, "de"),
                 %{type: :track, id: 99103, owner_id: actor.id},
                 %{},
                 now: S.now()
               )

      if preference,
        do: assert({:ok, %{trip: %{name: ^expected}}} = Read.track(user, 99103, S.now()))

      assert {:ok, _} =
               change(user, :track, 99103, :create, S.params("track", %{"name" => ""}), "de")

      assert Repo.query!(
               "SELECT name FROM shared_links WHERE user_id=$1 AND resource_type=1 AND revoked_at IS NULL",
               [actor.id]
             ).rows == [[expected]]
    end
  end

  @tag review_case: "F4-request"
  @tag :track_c_r2
  test "F4 native prefetched track manager preserves the resolved request locale", %{
    actor: actor
  } do
    settings = Map.put(actor.settings, "locale", "en")
    Repo.query!("UPDATE users SET settings=$2 WHERE id=$1", [actor.id, settings])
    Repo.query!("DELETE FROM shared_links WHERE user_id=$1 AND resource_type=1", [actor.id])
    session = RailsUser.session(actor.id, %{"locale" => "en"})

    response =
      Plug.Test.conn(:get, "/tracks/99103/share_link/new?locale=de")
      |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
      |> put_req_header("purpose", "prefetch")
      |> put_req_header("turbo-frame", "share-link-modal")
      |> assign(:now, S.now())
      |> DawarichWeb.Endpoint.call(DawarichWeb.Endpoint.init([]))

    assert response.status == 200
    assert response.assigns.locale == "de"
    assert String.contains?(response.resp_body, "Stationär · 3. Okt 2026 · 2 km")

    assert Repo.query!("SELECT settings->>'locale' FROM users WHERE id=$1", [actor.id]).rows == [
             ["en"]
           ]
  end
end
