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
    saved = Map.new(~w(SELF_HOSTED DAWARICH_RAILS JWT_SECRET_KEY), &{&1, System.get_env(&1)})
    System.put_env("SELF_HOSTED", "true")
    System.put_env("DAWARICH_RAILS", "off")
    System.put_env("JWT_SECRET_KEY", "synthetic-family-delivery")

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

  test "late location refusal erases the native presentation before rendering", c do
    view = open(c.owner)
    socket = :sys.get_state(view.pid).socket
    assert socket.assigns.page.presentation.members != []
    refute Map.has_key?(socket.assigns, :locations)
    Repo.query!("DELETE FROM family_memberships WHERE user_id=$1", [c.owner.id], log: false)
    assert {:halt, cleared} = DawarichWeb.NativeFamilyResource.admit(socket)
    assert cleared.assigns.page == nil
    assert cleared.assigns.map_error == :not_found

    html =
      DawarichWeb.FamiliesLive.NativeMap.render(cleared.assigns)
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    refute String.contains?(html, c.member.email)
  end

  test "withdrawn consent or removed membership discards queued coordinates before rendering",
       c do
    view = open(c.owner)
    assert [%{"user_id" => 90102}] = locations(view)

    Repo.query!(
      "UPDATE users SET settings=jsonb_set(settings,'{family,location_sharing,enabled}','false') WHERE id=90102",
      [],
      log: false
    )

    render_hook(view, "family:focus", %{"id" => "90102"})
    assert locations(view) == []
    send(view.pid, {:domain_changed, c.owner.id, :location})
    render(view)
    assert locations(view) == []
    refute Map.has_key?(state(view), :locations)

    Repo.query!(
      "UPDATE users SET settings=jsonb_set(settings,'{family,location_sharing,enabled}','true') WHERE id=90102",
      [],
      log: false
    )

    send(view.pid, {:domain_changed, c.owner.id, :consent})
    render(view)
    assert length(locations(view)) == 1
    Repo.query!("DELETE FROM family_memberships WHERE user_id=90102", [], log: false)
    send(view.pid, {:domain_changed, c.owner.id, :location})
    render(view)
    assert locations(view) == []
  end

  test "expiry clears family data without another point event and stale timers cannot clear a new grant",
       c do
    view = open(c.owner)
    first = state(view).native_family_consent
    assert is_reference(first.token) and is_reference(first.timer)
    grant(DateTime.add(DateTime.utc_now(), 7200))
    send(view.pid, {:native_family_consent, first.token})
    render(view)
    second = state(view).native_family_consent
    refute first.token == second.token
    assert Process.read_timer(first.timer) == false
    send(view.pid, {:native_family_consent, first.token})
    render(view)
    assert state(view).native_family_consent.token == second.token
    assert length(locations(view)) == 1
    grant(DateTime.add(DateTime.utc_now(), -1))
    send(view.pid, {:native_family_consent, second.token})
    render(view)
    assert locations(view) == []
    assert_push_event(view, "family:clear", %{code: "consent_expired"})
  end

  test "native family consent uses a bounded lease without selecting coordinates", c do
    view = open(c.owner)
    handler = "family-delivery-deadline-#{System.unique_integer([:positive])}"
    parent = self()
    pid = view.pid

    :telemetry.attach(
      handler,
      [:dawarich, :repo, :query],
      fn _, _, metadata, _ ->
        if self() == pid and String.contains?(metadata.query, "ST_X"),
          do: send(parent, :family_coordinate_query)
      end,
      nil
    )

    try do
      send(view.pid, {:domain_changed, c.owner.id, :consent})
      render(view)
    after
      :telemetry.detach(handler)
    end

    assert state(view).native_family_consent.milliseconds <= 30_000
    refute_received :family_coordinate_query
  end

  test "reconnect snapshots recover missed invalidation and family refusal clears private state",
       c do
    view = open(c.owner)
    assert length(locations(view)) == 1

    Repo.query!(
      "UPDATE users SET settings=jsonb_set(settings,'{family,location_sharing,enabled}','false') WHERE id=90102",
      [],
      log: false
    )

    GenServer.stop(view.pid)
    connected = open(c.owner)
    assert locations(connected) == []
    Repo.query!("DELETE FROM family_memberships WHERE user_id=$1", [c.owner.id], log: false)
    send(connected.pid, {:domain_changed, c.owner.id, :membership})
    render(connected)
    assert state(connected).page == nil
    refute has_element?(connected, "#family-shell")
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

  test "a member's own Cloud subscription schedules silent expiry on show and invitation pages",
       c do
    System.put_env("SELF_HOSTED", "false")
    expiry = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_naive()

    Repo.query!(
      "UPDATE families SET access_until=$1 WHERE id=91001",
      [NaiveDateTime.add(expiry, -7200)],
      log: false
    )

    Repo.query!("UPDATE users SET plan=1 WHERE id=90101", [], log: false)
    Repo.query!("UPDATE users SET plan=2,active_until=$1 WHERE id=90102", [expiry], log: false)

    Repo.query!(
      "UPDATE users SET settings=jsonb_set(settings,'{family,location_sharing}', $1::jsonb) WHERE id IN (90101,90102)",
      [%{"enabled" => true, "duration" => "permanent"}],
      log: false
    )

    Repo.query!("DELETE FROM family_invitations", [], log: false)
    Repo.query!("DELETE FROM family_location_requests", [], log: false)

    Repo.query!(
      "INSERT INTO points(user_id,lonlat,timestamp,created_at,updated_at) VALUES(90101,ST_SetSRID(ST_MakePoint(0,0),4326),$1,now(),now())",
      [DateTime.to_unix(DateTime.utc_now())],
      log: false
    )

    scope = Dawarich.Accounts.Scope.for_user(c.member, "en")
    assert {:ok, %{deadline: ^expiry, locations: [_ | _]}} = Families.locations(scope)
    assert {:ok, ^expiry} = Families.deadline(scope)
    show = open(c.member)

    {:ok, invitations, _} =
      live(
        RailsUser.signed_in(c.member.id) |> RailsUser.connecting_as(c.member.id),
        "/family/invitations"
      )

    assert state(show).native_family_consent.milliseconds <= 30_000
    assert Process.read_timer(state(show).native_family_consent.timer) > 0
    assert state(invitations).family_expiry.due == expiry
    assert locations(show) != []

    Repo.query!(
      "UPDATE users SET active_until=$1 WHERE id=90102",
      [NaiveDateTime.add(expiry, -7200)],
      log: false
    )

    send(show.pid, {:native_family_consent, state(show).native_family_consent.token})
    render(show)
    assert state(show).page == nil
    assert locations(show) == []
    send(invitations.pid, {:family_expiry, state(invitations).family_expiry.token})
    render(invitations)
    refute state(invitations).page.live?
    assert state(invitations).family_expiry == nil
    assert state(invitations).locations == []
  end

  defp locations(view) do
    scope = state(view).current_scope

    case Dawarich.Maps.Family.read(scope, :locations, %{},
           self_hosted: System.get_env("SELF_HOSTED") != "false"
         ) do
      {:ok, 200, body} -> body.locations
      _ -> []
    end
  end
end
