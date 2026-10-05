defmodule DawarichWeb.AuthApi.ResponseTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias DawarichWeb.Api.{Auth, Body}
  alias DawarichWeb.AuthApi.Response
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.{Repo, Test.RailsUser}
  @rows "test/fixtures/auth/api_auth/login.json" |> File.read!() |> Jason.decode!()

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    RailsUser.insert!(%{
      id: 75_910,
      email: "a11f-response-caller@example.invalid",
      api_key: "a11f-caller-sentinel",
      settings: %{"timezone" => "Europe/Berlin"}
    })

    :ok
  end

  test "API auth responses match source status bytes headers and absence of web sessions" do
    for {name, bearer} <- [
          {"json", nil},
          {"caller-bearer", "a11f-caller-sentinel"},
          {"caller-unknown", "unknown"},
          {"otp-configured-enabled", nil}
        ],
        locale <- ["en", "de"] do
      row = Enum.find(@rows, &(&1["name"] == name))
      body = row["response"]["body"]
      term = Jason.decode!(body, objects: :ordered_objects).values |> then(&{:object, &1})

      conn =
        Plug.Test.conn("POST", "/api/v1/auth/login", "{}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("content-length", "2")
        |> put_req_header("accept", "application/json")
        |> put_req_header("accept-language", locale)
        |> assign(:api_tag, "api")

      conn = if bearer, do: put_req_header(conn, "authorization", "Bearer " <> bearer), else: conn
      conn = conn |> Body.call([]) |> Auth.public()
      assert Response.preflight(conn, term) == :ok

      result =
        if row["response"]["status"] == 202,
          do: Response.challenge(conn, "runtime:challenge_token"),
          else: Response.success(conn, term)

      assert result.status == row["response"]["status"] and result.halted
      assert result.resp_body == body
      assert get_resp_header(result, "set-cookie") == []
      assert get_resp_header(result, "x-dawarich-auth-owner") == ["native-api-auth"]
      expected = row["response"]["headers"] |> Map.drop(~w(x-request-id x-runtime etag))

      actual =
        Map.new(result.resp_headers)
        |> Map.drop(~w(x-request-id x-runtime etag x-dawarich-auth-owner cache-control))

      assert actual == Map.drop(expected, ["cache-control"])
      assert get_resp_header(result, "cache-control") == [expected["cache-control"]]
      assert [runtime] = get_resp_header(result, "x-runtime")
      assert runtime =~ ~r/\A[0-9]+\.[0-9]{6}\z/

      if result.status == 200 do
        digest =
          :crypto.hash(:sha256, result.resp_body)
          |> Base.encode16(case: :lower)
          |> binary_part(0, 32)

        assert get_resp_header(result, "etag") == [~s(W/"#{digest}")]
      else
        assert get_resp_header(result, "etag") == []
        fields = Jason.decode!(result.resp_body)
        assert Map.keys(fields) |> Enum.sort() == ~w(challenge_token ttl two_factor_required)
        refute Map.has_key?(fields, "api_key")
        assert fields["ttl"] == 300
      end

      assert Ruby.json(term) |> IO.iodata_to_binary() == body
    end
  end
end
