defmodule DawarichWeb.HostAuthorizationTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias DawarichWeb.{HostAuthorization, Slices}

  @units "test/fixtures/ingest/units.json" |> File.read!() |> Jason.decode!()

  test "allows and blocks exactly as ActionDispatch::HostAuthorization with Rails' host lists" do
    for row <- @units["hosts"] do
      conn =
        conn(:post, "/api/v1/points")
        |> then(fn conn ->
          if row["host"],
            do: %{conn | req_headers: [{"host", row["host"]} | conn.req_headers]},
            else: conn
        end)
        |> then(fn conn ->
          Enum.reduce(
            [
              {"x-forwarded-host", row["forwarded"]},
              {"x-requested-with", row["xhr"] && "XMLHttpRequest"}
            ],
            conn,
            fn
              {_name, value}, acc when value in [nil, false] -> acc
              {name, value}, acc -> put_req_header(acc, name, value)
            end
          )
        end)

      result =
        HostAuthorization.call(conn,
          env: %{
            "RAILS_ENV" => row["rails_env"],
            "APPLICATION_HOSTS" => row["application_hosts"]
          }
        )

      case row["result"] do
        "allowed" ->
          refute result.halted, inspect(row)

        %{"status" => 403, "content-type" => type, "body" => ""} ->
          assert {403, ^type, ""} =
                   {result.status, hd(get_resp_header(result, "content-type")), result.resp_body},
                 inspect(row)

          assert get_resp_header(result, "cache-control") == []
          assert result.halted, inspect(row)
      end
    end
  end

  test "ingest is owned on self-hosted installs unless DAWARICH_RAILS_SLICES names it" do
    on_exit(fn ->
      System.delete_env("SELF_HOSTED")
      System.delete_env("DAWARICH_RAILS_SLICES")
    end)

    assert Slices.owned?(:ingest)
    System.put_env("DAWARICH_RAILS_SLICES", " Ingest ,notifications")
    refute Slices.owned?(:ingest)
    System.delete_env("DAWARICH_RAILS_SLICES")
    System.put_env("SELF_HOSTED", "false")
    refute Slices.owned?(:ingest)
  end
end
