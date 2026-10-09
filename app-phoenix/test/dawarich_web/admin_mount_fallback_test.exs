defmodule DawarichWeb.AdminMountFallbackTest do
  use ExUnit.Case, async: true

  alias DawarichWeb.SettingsLive.{UserEdit, UserShow, UsersIndex}

  test "mount-time Rails fallbacks retain the original query parameters" do
    for {view, path, params, query} <- [
          {UsersIndex, "/settings/users", %{"search" => "literal %_", "page" => "2"},
           %{"search" => "literal %_", "page" => "2"}},
          {UserShow, "/settings/users/10001", %{"id" => "10001"}, %{"section" => "account"}},
          {UserEdit, "/settings/users/10001/edit", %{"id" => "10001"}, %{"section" => "account"}}
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
