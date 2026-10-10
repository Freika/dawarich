defmodule DawarichWeb.FamilyNativeDeliveryTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.{Accounts, Families, Repo}
  alias Dawarich.Test.{FrameSeeds, RailsUser}
  @endpoint DawarichWeb.Endpoint

  setup do
    Code.ensure_loaded!(Dawarich.Accounts.User)
    owner = FrameSeeds.seed_family!(FrameSeeds.load_family("consented_map_en"))
    saved = Map.new(~w(SELF_HOSTED DAWARICH_RAILS), &{&1, System.get_env(&1)})
    System.put_env("SELF_HOSTED", "true")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      for {key, value} <- saved,
          do: if(value, do: System.put_env(key, value), else: System.delete_env(key))
    end)

    grant(DateTime.add(DateTime.utc_now(), 3600))
    %{owner: owner, member: Accounts.get(90102)}
  end

  defp open(user) do
    {:ok, view, html} =
      live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), "/family")

    refute html =~ "51.3397"
    view
  end

  defp state(view), do: :sys.get_state(view.pid).socket.assigns

  defp grant(at) do
    Repo.query!(
      "UPDATE users SET settings=jsonb_set(settings,'{family,location_sharing,expires_at}',to_jsonb($1::text)) WHERE id=90102",
      [DateTime.to_iso8601(at)],
      log: false
    )
  end

  test "withdrawn consent or removed membership discards queued coordinates before rendering",
       c do
    view = open(c.owner)
    assert [%{"user_id" => 90102}] = state(view).locations

    Repo.query!(
      "UPDATE users SET settings=jsonb_set(settings,'{family,location_sharing,enabled}','false') WHERE id=90102",
      [],
      log: false
    )

    render_hook(view, "family_focus", %{"id" => "90102"})
    assert state(view).locations == []
    send(view.pid, {:domain_changed, c.owner.id, :location})
    render(view)
    assert state(view).locations == []
    assert_push_event(view, "family-locations", %{locations: []})

    Repo.query!(
      "UPDATE users SET settings=jsonb_set(settings,'{family,location_sharing,enabled}','true') WHERE id=90102",
      [],
      log: false
    )

    send(view.pid, {:domain_changed, c.owner.id, :consent})
    render(view)
    assert length(state(view).locations) == 1
    Repo.query!("DELETE FROM family_memberships WHERE user_id=90102", [], log: false)
    send(view.pid, {:domain_changed, c.owner.id, :location})
    render(view)
    assert state(view).locations == []
  end

  test "expiry clears family data without another point event and stale timers cannot clear a new grant",
       c do
    view = open(c.owner)
    first = state(view).family_expiry
    assert is_reference(first.token) and is_reference(first.timer)
    grant(DateTime.add(DateTime.utc_now(), 7200))
    send(view.pid, {:domain_changed, c.owner.id, :consent})
    render(view)
    second = state(view).family_expiry
    refute first.token == second.token
    assert Process.read_timer(first.timer) == false
    send(view.pid, {:family_expiry, first.token})
    render(view)
    assert state(view).family_expiry.token == second.token
    assert length(state(view).locations) == 1
    grant(DateTime.add(DateTime.utc_now(), -1))
    send(view.pid, {:family_expiry, second.token})
    render(view)
    assert state(view).locations == []
    assert state(view).family_expiry == nil
  end

  test "reconnect snapshots recover missed invalidation and family refusal clears private state",
       c do
    view = open(c.owner)
    assert length(state(view).locations) == 1

    Repo.query!(
      "UPDATE users SET settings=jsonb_set(settings,'{family,location_sharing,enabled}','false') WHERE id=90102",
      [],
      log: false
    )

    GenServer.stop(view.pid)
    connected = open(c.owner)
    assert state(connected).locations == []
    Repo.query!("DELETE FROM family_memberships WHERE user_id=$1", [c.owner.id], log: false)
    send(connected.pid, {:domain_changed, c.owner.id, :membership})
    assert_redirect(connected, "/family/new")
  end

  test "a native family creation tab subscribes before membership without granting location access",
       _c do
    outsider = Accounts.get(90103)

    {:ok, view, _} =
      live(
        RailsUser.signed_in(outsider.id) |> RailsUser.connecting_as(outsider.id),
        "/family/new"
      )

    assert state(view).locations == []
    scope = Dawarich.Accounts.Scope.for_user(outsider, "en")
    assert {:ok, _} = Families.create(scope, %{"name" => "Other tab family"})
    Dawarich.Families.Events.broadcast(outsider.id, :membership)
    assert_redirect(view, "/family")
  end
end
