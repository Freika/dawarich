defmodule DawarichWeb.ImportsProviderEventsTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.Repo
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint

  setup do
    user =
      RailsUser.insert!(%{
        id: 11071,
        email: "providers@example.invalid",
        settings: %{
          "timezone" => "UTC",
          "immich_url" => "https://synthetic.invalid",
          "immich_api_key" => "synthetic-provider-key",
          "onboarding_completed" => true
        }
      })

    for kind <- ~w(imports.immich_geodata imports.photoprism_geodata),
        do: Dawarich.Jobs.Ownership.put!(Repo, "command:" <> kind, :oban)

    %{user: user}
  end

  defp live_as(user),
    do: live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), "/imports")

  defp queued, do: Repo.query!("SELECT command_type,payload FROM job_outbox", [], log: false).rows

  test "provider events recheck eligibility and dispatch one accepted command", c do
    {:ok, view, _} = live_as(c.user)

    assert has_element?(
             view,
             "button[phx-click=request_provider][phx-value-job=start_immich_import]"
           )

    Repo.query!("UPDATE users SET settings=settings-'immich_api_key' WHERE id=$1", [c.user.id],
      log: false
    )

    render_hook(view, "request_provider", %{"job" => "start_immich_import"})
    assert queued() == []
    assert has_element?(view, "[role=alert]")

    Repo.query!(
      "UPDATE users SET settings=settings||$2::jsonb WHERE id=$1",
      [c.user.id, %{"immich_api_key" => "synthetic-provider-key"}],
      log: false
    )

    render_hook(view, "request_provider", %{"job" => "start_immich_import"})
    render_hook(view, "request_provider", %{"job" => "start_immich_import"})

    assert queued() == [
             ["imports.immich_geodata", %{"user_id" => c.user.id, "time_zone" => "Etc/UTC"}]
           ]

    assert render(view) =~ "Job was successfully created."
    assert has_element?(view, "button[phx-click=request_provider][disabled]")
  end

  test "unconfigured or forged job names publish nothing and expose no credentials", c do
    {:ok, view, html} = live_as(c.user)

    for value <- [
          html,
          inspect(:sys.get_state(view.pid), limit: :infinity, printable_limit: :infinity)
        ] do
      refute value =~ "synthetic-provider-key"
      refute value =~ "synthetic.invalid"
    end

    for job <- [
          "start_photoprism_import",
          "start_airtrail_import",
          "start_reverse_geocoding",
          "unknown"
        ] do
      render_hook(view, "request_provider", %{"job" => job})
    end

    assert queued() == []
    scope = :sys.get_state(view.pid).socket.assigns.current_scope

    for name <- ["start_airtrail_import", "start_reverse_geocoding", "unknown"],
        do:
          assert(
            {:error, :unknown_job} == apply(Dawarich.Imports, :request_provider, [scope, name])
          )

    Repo.query!(
      "UPDATE users SET active_until=now()-interval '1 second' WHERE id=$1",
      [c.user.id],
      log: false
    )

    assert {:error, :inactive} =
             apply(Dawarich.Imports, :request_provider, [scope, "start_immich_import"])

    assert queued() == []
  end
end
