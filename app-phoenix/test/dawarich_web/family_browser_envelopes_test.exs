defmodule DawarichWeb.FamilyBrowserEnvelopesTest do
  use Dawarich.JobsCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  import Phoenix.LiveViewTest
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.RailsCsrf
  @endpoint DawarichWeb.Endpoint
  @delete_prompt "Delete this family? This cannot be undone."

  setup do
    context = Dawarich.Test.FamilyCorpus.seed()
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
  test "native map confirmed leave removes one membership and navigates to family creation", c do
    view = open(c.member)
    confirm(view, "remove_member", "92002", "Are you sure you want to leave this family?")
    assert_redirect(view, "/family/new")
    assert records("SELECT count(*) FROM family_memberships WHERE id=92002") == [[0]]
  end

  @tag :sa_g44_families_remove
  test "native map confirmed removal preserves the owner and removes the member", c do
    view = open(c.owner)
    confirm(view, "remove_member", "92002", "Remove #{c.member.email} from the family?")
    assert has_element?(view, "#family-shell")
    assert records("SELECT id FROM family_memberships WHERE family_id=91001") == [[92001]]
  end

  @tag :sa_g44_families_accept
  test "HTTP invitation acceptance joins once and native map departure removes the joined member",
       c do
    response =
      browser(c.outsider, "/family/memberships?token=a9fpl-pending", %{"_method" => "post"})

    assert response.status == 302
    assert get_resp_header(response, "location") == ["http://www.example.com/family"]
    assert [[id]] = records("SELECT id FROM family_memberships WHERE user_id=90103")

    view = open(Accounts.get(c.outsider.id))

    confirm(
      view,
      "remove_member",
      Integer.to_string(id),
      "Are you sure you want to leave this family?"
    )

    assert_redirect(view, "/family/new")
    assert records("SELECT count(*) FROM family_memberships WHERE user_id=90103") == [[0]]
  end

  @tag :sa_g44_families_delete
  test "native map deletion refuses members until the owner removes them", c do
    view = open(c.owner)
    confirm(view, "delete", nil, @delete_prompt)
    assert has_element?(view, "[role=alert]")
    assert records("SELECT count(*) FROM families WHERE id=91001") == [[1]]
    confirm(view, "remove_member", "92002", "Remove #{c.member.email} from the family?")
    confirm(view, "delete", nil, @delete_prompt)
    assert_redirect(view, "/family/new")
    assert records("SELECT count(*) FROM families WHERE id=91001") == [[0]]
  end

  @tag :sa_g44_families_history
  test "native map sharing form persists live location and history consent", c do
    assert sharing(c.owner, true) == :ok
    assert sharing(c.owner, true, %{"duration" => "1h"}) == :ok
    assert sharing(c.owner, true, %{"duration" => "1h", "share_history" => "true"}) == :ok

    response =
      sharing(c.owner, true, %{
        "duration" => "1h",
        "share_history" => "true",
        "history_window" => "30d"
      })

    assert response == :ok

    settings = Accounts.settings(c.owner.id)["family"]["location_sharing"]
    assert settings["enabled"]
    assert settings["share_history"]
    assert settings["history_window"] == "30d"
  end

  @tag :sa_g44_families_map
  test "native map sharing command admits only consenting members and removes revoked consent",
       c do
    Repo.query!("UPDATE users SET settings=settings-'family' WHERE id IN (90101,90102)")

    Repo.query!(
      "INSERT INTO points(user_id,timestamp,lonlat,created_at,updated_at) VALUES($1,1791021600,ST_SetSRID(ST_MakePoint(13.406,52.521),4326),now(),now())",
      [c.member.id]
    )

    assert locations(c.owner) == []
    assert sharing(c.member, true) == :ok
    assert [%{"user_id" => 90102}] = locations(c.owner)
    assert sharing(c.member, false) == :ok
    assert locations(c.owner) == []
  end

  defp sharing(user, enabled, attrs \\ %{}) do
    view = open(user)

    view
    |> render_hook("family:sharing", %{
      sharing:
        Map.merge(
          %{
            "enabled" => to_string(enabled),
            "duration" => "permanent",
            "share_history" => "false",
            "history_window" => "7d"
          },
          attrs
        )
    })

    :ok
  end

  defp open(user),
    do: elem(live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), "/family"), 1)

  defp confirm(view, action, id, prompt) do
    selector =
      "[data-native-family-action='#{action}']" <>
        if(id, do: "[data-native-family-target='#{id}']", else: "")

    effects =
      "SELECT (SELECT count(*) FROM families), (SELECT count(*) FROM family_memberships)"

    before = records(effects)
    view |> element(selector) |> render_click()
    assert has_element?(view, "#family-confirm[data-pending=true] p", prompt)
    assert records(effects) == before
    view |> element("#family-confirm button[phx-click='family_confirm']") |> render_click()
  end

  defp browser(user, path, params) do
    session = RailsUser.session(user.id)

    body =
      Map.put(params, "authenticity_token", RailsCsrf.masked_token(session))
      |> Plug.Conn.Query.encode()

    build_conn()
    |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", to_string(byte_size(body)))
    |> put_req_header("origin", "http://www.example.com")
    |> assign(:now, ~U[2026-10-03 10:00:00Z])
    |> post(path, body)
  end

  defp locations(user) do
    RailsUser.signed_in(user.id)
    |> assign(:now, ~U[2026-10-03 10:00:00Z])
    |> get("/family/locations.json")
    |> json_response(200)
  end

  defp records(sql), do: Repo.query!(sql).rows
end
