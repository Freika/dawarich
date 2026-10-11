defmodule Dawarich.Test.GoldenCookies do
  @moduledoc false
  import ExUnit.Assertions
  alias Dawarich.{RailsCookies, RailsSecret}

  def headers(headers, kase, now) do
    Enum.map(headers, fn
      {"set-cookie", cookie} ->
        [pair | attributes] = String.split(cookie, "; ")
        [name, value] = String.split(pair, "=", parts: 2)

        expected =
          kase["cookie_attributes"] ||
            %{
              "name" => "_dawarich_session",
              "attributes" => ["path=/", "httponly", "samesite=lax"]
            }

        assert name == expected["name"]

        assert Enum.sort(Enum.map(attributes, &String.downcase/1)) ==
                 Enum.sort(Enum.map(expected["attributes"], &String.downcase/1))

        if name == "_dawarich_session" do
          assert {:ok, session} = RailsCookies.decrypt(value, name, RailsSecret.fetch(), now)
          assert session["session_id"] =~ ~r/\A[0-9a-f]{32}\z/
          assert Map.drop(session, ["session_id", "_csrf_token"]) == kase["session_after"]
        else
          assert name == "remember_user_token"
          assert value == ""
        end

        {"set-cookie", "redacted"}

      pair ->
        pair
    end)
  end
end
