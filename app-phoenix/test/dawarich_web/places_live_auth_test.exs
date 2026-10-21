defmodule DawarichWeb.PlacesLiveAuthTest do
  use ExUnit.Case, async: false
  import Phoenix.LiveViewTest
  import Phoenix.ConnTest
  alias Dawarich.Test.NativePlaces, as: N
  @endpoint DawarichWeb.Endpoint
  setup do: N.setup!()

  test "native Places refuse revoked identity on event params info and async", ctx do
    for channel <- [:event, :params, :info] do
      {:ok, view, _} = live(N.conn(ctx.actor), "/places")
      N.revoke(ctx.actor)

      case channel do
        :event -> render_click(view, "request_delete", %{"id" => "118501"})
        :params -> render_patch(view, "/places?page=2")
        :info -> send(view.pid, :places_probe)
      end

      assert_redirect(view, "/users/sign_in")

      Dawarich.Repo.query!(
        "UPDATE users SET encrypted_password=$1 WHERE id=$2",
        [ctx.actor.encrypted_password, ctx.actor.id],
        log: false
      )
    end

    {:ok, view, _} = live(N.conn(ctx.actor), "/places")
    socket = :sys.get_state(view.pid).socket
    N.revoke(ctx.actor)
    socket = Phoenix.Component.assign(socket, :current_user, Dawarich.Accounts.get(ctx.actor.id))

    for delivery <- [
          fn -> Phoenix.LiveView.Lifecycle.handle_event("unknown", %{}, socket) end,
          fn -> Phoenix.LiveView.Lifecycle.handle_params(%{}, "/places", socket) end,
          fn -> Phoenix.LiveView.Lifecycle.handle_info(:places_probe, socket) end,
          fn -> Phoenix.LiveView.Lifecycle.handle_async(:nearby, {:ok, []}, socket) end
        ] do
      assert {:halt, refused} = delivery.()
      assert refused.redirected == {:redirect, %{to: "/users/sign_in", status: 302}}
      assert refused.assigns.entries == []
    end

    assert Dawarich.Repo.query!("SELECT id FROM places WHERE user_id=$1", [ctx.actor.id]).rows ==
             []
  end

  test "Places assigns exclude account credentials across mount event info and async", ctx do
    secrets = Enum.map(1..4, &"synthetic-places-credential-#{&1}")
    [api_key, integration_key, password, token] = secrets

    settings = %{
      "timezone" => "Europe/Berlin",
      "onboarding_completed" => true,
      "immich_api_key" => integration_key,
      "teslamate_password" => password,
      "teslamate_api_token" => token
    }

    Dawarich.Repo.query!(
      "UPDATE users SET api_key=$1,settings=$2 WHERE id=$3",
      [api_key, settings, ctx.actor.id],
      log: false
    )

    previous = Application.get_env(:dawarich, :native_places_nearby_opts)

    Application.put_env(:dawarich, :native_places_nearby_opts,
      fetch: fn _, _, _, _, _, _ ->
        [%{"name" => "Safe", "latitude" => 51.2, "longitude" => 12.2}]
      end
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:dawarich, :native_places_nearby_opts, previous),
        else: Application.delete_env(:dawarich, :native_places_nearby_opts)
    end)

    {:ok, view, _} = live(N.conn(ctx.actor), "/places")
    assert_credentials_absent(view, secrets)
    assert current_tracking_qr?(view) == true
    render_click(view, "open_create", %{})
    assert_credentials_absent(view, secrets)
    gen = N.generation(view, :form_state)

    render_change(view, "validate_place", %{
      "generation" => gen,
      "place" => %{"name" => "Draft", "latitude" => "51", "longitude" => "12"}
    })

    send(view.pid, :navbar_refresh)
    render(view)
    assert_credentials_absent(view, secrets)
    render_click(view, "nearby", %{"generation" => gen})
    render_async(view)
    assert has_element?(view, "[data-nearby-state=results]", "Safe")
    assert_credentials_absent(view, secrets)
    render_click(view, "changelog_consent", %{"decision" => "declined"})
    assert_credentials_absent(view, secrets)
    assert :sys.get_state(view.pid).socket.assigns.current_user.changelog_consent == 0
  end

  defp current_tracking_qr?(view) do
    html = render(view)
    doc = LazyHTML.from_fragment(html)

    LazyHTML.query(doc, "#native-onboarding-api-qr[phx-hook=CredentialQr]") |> Enum.count() == 1 and
      LazyHTML.query(doc, "#native-onboarding-api-qr svg") |> Enum.empty?()
  end

  defp assert_credentials_absent(view, secrets) do
    assigns = :sys.get_state(view.pid).socket.assigns
    assert contains_credentials?(assigns, secrets) == false
  end

  defp contains_credentials?(value, secrets) when is_binary(value),
    do: Enum.any?(secrets, &String.contains?(value, &1))

  defp contains_credentials?(value, secrets) when is_map(value),
    do: value |> Map.to_list() |> contains_credentials?(secrets)

  defp contains_credentials?(value, secrets) when is_tuple(value),
    do: value |> Tuple.to_list() |> contains_credentials?(secrets)

  defp contains_credentials?(value, secrets) when is_list(value),
    do: Enum.any?(value, &contains_credentials?(&1, secrets))

  defp contains_credentials?(_, _), do: false

  test "native Places unavailable initial admission mounts a safe local alert", _ctx do
    actor = %Dawarich.Accounts.User{
      id: Integer.pow(10, 100),
      encrypted_password: "synthetic",
      api_key: "synthetic-unavailable-credential",
      settings: %{"immich_api_key" => "synthetic-unavailable-credential"}
    }

    socket = %Phoenix.LiveView.Socket{
      router: DawarichWeb.Router,
      assigns: %{
        __changed__: %{},
        current_scope: Dawarich.Accounts.Scope.for_user(actor, "en"),
        locale: "en"
      },
      private: %{lifecycle: %Phoenix.LiveView.Lifecycle{}}
    }

    assert {:cont, refused} = DawarichWeb.PlacesLiveAuth.on_mount(:default, %{}, %{}, socket)
    assert refused.redirected == nil
    assert refused.assigns.error == DawarichWeb.PlacesUI.message("en")
    assert contains_credentials?(refused.assigns, ["synthetic-unavailable-credential"]) == false
  end
end
