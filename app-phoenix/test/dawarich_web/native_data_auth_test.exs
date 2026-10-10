defmodule DawarichWeb.NativeDataAuthTest do
  use ExUnit.Case, async: false
  alias Dawarich.Accounts.Scope
  alias Dawarich.Accounts.Principal
  alias Dawarich.Test.NativeAdminUI
  alias DawarichWeb.NativeDataAuth

  setup do
    %{target: user} = NativeAdminUI.setup!()

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        locale: "en",
        current_user: user,
        current_scope: Scope.for_user(user, "en"),
        rows: [%{id: 1}],
        flash: %{}
      },
      private: %{
        data_principal: Principal.scope(Scope.for_user(user, "en")),
        live_temp: %{}
      }
    }

    %{socket: socket, user: user}
  end

  test "data params and async delivery refuse a changed identity before projection", %{
    socket: socket,
    user: user
  } do
    socket = %{
      socket
      | router: DawarichWeb.Router,
        view: DawarichWeb.PointsLive.Index,
        endpoint: DawarichWeb.Endpoint,
        private: Map.put(socket.private, :lifecycle, %Phoenix.LiveView.Lifecycle{})
    }

    session = %{
      "rails_user_id" => user.id,
      "locale" => "en",
      "self_hosted" => true,
      "request_path" => "/points"
    }

    assert {:cont, socket} = NativeDataAuth.on_mount(:require_user, %{}, session, socket)

    Dawarich.Repo.query!(
      "UPDATE users SET encrypted_password = 'changed-00000000000000000000000' WHERE id = $1",
      [user.id],
      log: false
    )

    callbacks = [
      fn -> Phoenix.LiveView.Lifecycle.handle_params(%{}, "http://localhost/points", socket) end,
      fn ->
        Phoenix.LiveView.Lifecycle.handle_event(
          "changelog_consent",
          %{"decision" => "granted"},
          socket
        )
      end,
      fn -> Phoenix.LiveView.Lifecycle.handle_info(:navbar_refresh, socket) end,
      fn -> Phoenix.LiveView.Lifecycle.handle_async(:details, {:ok, :private_data}, socket) end
    ]

    for callback <- callbacks do
      assert {:halt, refused} = callback.()
      assert refused.redirected == {:redirect, %{to: "/users/sign_in", status: 302}}
      refute Map.has_key?(refused.assigns, :rows)
      refute Map.has_key?(refused.assigns, :current_scope)
    end

    assert Dawarich.Accounts.get(user.id).changelog_consent == user.changelog_consent
  end

  test "data refusals use their own destinations", %{socket: socket} do
    assert NativeDataAuth.refuse(socket, :stale_session).redirected ==
             {:redirect, %{to: "/users/sign_in", status: 302}}

    assert NativeDataAuth.refuse(socket, :not_found, "/points").redirected ==
             {:redirect, %{to: "/points", status: 302}}

    assert is_nil(NativeDataAuth.refuse(socket, :invalid_input).redirected)
    assert is_nil(NativeDataAuth.refuse(socket, :unavailable).redirected)
  end

  test "admitted socket assigns never retain credential or provider settings", %{
    socket: socket,
    user: user
  } do
    assert {:cont, admitted} = NativeDataAuth.authorize(socket, :params)
    refute :erlang.term_to_binary(admitted.assigns) =~ user.api_key
    refute :erlang.term_to_binary(admitted.assigns) =~ user.encrypted_password
    refute Map.has_key?(admitted.assigns, :current_scope)
    assert {:ok, scope} = NativeDataAuth.scope(admitted)
    assert scope.user.id == user.id
  end
end
