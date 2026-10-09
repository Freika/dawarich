defmodule DawarichWeb.AdminMountFallbackTest do
  use ExUnit.Case, async: true

  alias DawarichWeb.AdminLive.Instance
  alias DawarichWeb.SettingsLive.{UserEdit, UserShow, UsersIndex}

  test "native users index stale read redirects to sign-in" do
    socket = %Phoenix.LiveView.Socket{
      endpoint: DawarichWeb.Endpoint,
      assigns: %{__changed__: %{}, current_scope: nil, flash: %{}}
    }

    assert {:noreply, refused} =
             UsersIndex.handle_params(%{}, "http://www.example.com/settings/users", socket)

    assert refused.redirected == {:redirect, %{to: "/users/sign_in", status: 302}}
  end

  test "native user detail stale read clears credentials and redirects to sign-in" do
    socket = %Phoenix.LiveView.Socket{
      endpoint: DawarichWeb.Endpoint,
      assigns: %{__changed__: %{}, current_scope: nil, target: nil, target_user: nil, flash: %{}}
    }

    assert {:noreply, refused} =
             UserShow.handle_params(
               %{"id" => "10001"},
               "http://www.example.com/settings/users/10001",
               socket
             )

    assert refused.assigns.target_user == nil
    assert refused.redirected == {:redirect, %{to: "/users/sign_in", status: 302}}
  end

  test "native user edit stale read redirects to sign-in" do
    socket = %Phoenix.LiveView.Socket{
      endpoint: DawarichWeb.Endpoint,
      assigns: %{__changed__: %{}, current_scope: nil, target: nil, flash: %{}}
    }

    assert {:noreply, refused} =
             UserEdit.handle_params(
               %{"id" => "10001"},
               "http://www.example.com/settings/users/10001/edit",
               socket
             )

    assert refused.redirected == {:redirect, %{to: "/users/sign_in", status: 302}}
  end

  test "mount-time Rails fallbacks retain the original query parameters" do
    for {view, path, params, query} <- [
          {Instance, "/admin/settings", %{"section" => "geoapify"}, %{"section" => "geoapify"}}
        ] do
      socket = %Phoenix.LiveView.Socket{
        endpoint: DawarichWeb.Endpoint,
        assigns: %{
          __changed__: %{},
          current_user: nil,
          request_path: path,
          query_params: query,
          repo: nil,
          flash: %{}
        }
      }

      assert {:ok, fallback} = view.mount(params, %{}, socket)

      assert fallback.redirected ==
               {:redirect, %{to: path <> "?" <> URI.encode_query(query), status: 302}}
    end
  end
end
