defmodule DawarichWeb.AuthApi.InputTest do
  use ExUnit.Case, async: true
  alias DawarichWeb.AuthApi.Input
  import Plug.Conn

  test "API auth inputs admit source JSON and forms while preserving excluded bytes" do
    for {action, body, type, expected} <- [
          {:login, ~s({"email":"A@EXAMPLE.INVALID","password":"päss"}), "application/json",
           %{"email" => "A@EXAMPLE.INVALID", "password" => "päss"}},
          {:login, ~s({"email":null,"password":null}), "application/json",
           %{"email" => nil, "password" => nil}},
          {:login, "email=a%40example.invalid&password=a%26b",
           "application/x-www-form-urlencoded",
           %{"email" => "a@example.invalid", "password" => "a&b"}},
          {:challenge, ~s({"challenge_token":"synthetic","otp_code":"012345"}),
           "application/json", %{"challenge_token" => "synthetic", "otp_code" => "012345"}}
        ] do
      conn = conn(body, type)
      assert Input.precheck(conn) == :ok
      assert {:ok, params} = Input.select(conn, action)
      assert params == expected
      assert conn.private.dawarich_raw_body == body
    end

    for {body, type} <- [
          {~s({"email":"a","email":"b","password":"p"}), "application/json"},
          {"email=a&email=b&password=p", "application/x-www-form-urlencoded"},
          {"email=a&password=%xy", "application/x-www-form-urlencoded"},
          {"email=a&password=%FF", "application/x-www-form-urlencoded"},
          {~s({"email":[],"password":"p"}), "application/json"},
          {~s({"email":1,"password":"p"}), "application/json"},
          {~s({"email":true,"password":"p"}), "application/json"},
          {~s({"email":"a","password":"p","api_key":"caller"}), "application/json"},
          {~s({"email":"a","password":"p","extra":null}), "application/json"},
          {~s([{"email":"a"}]), "application/json"},
          {"{", "application/json"},
          {<<255>>, "application/json"},
          {"email[x]=a&password=p", "application/x-www-form-urlencoded"},
          {"email=a&_method=DELETE", "application/x-www-form-urlencoded"}
        ] do
      original = conn(body, type)
      assert {:replay, _} = Input.select(original, :login)
      assert original.private.dawarich_raw_body == body
    end

    original = conn(~s({"email":"a","password":"p"}), "application/json")

    for changed <- [
          %{original | query_string: "extra=1"},
          put_req_header(original, "content-length", "16385"),
          put_req_header(original, "content-length", "invalid"),
          put_req_header(original, "content-length", "3"),
          delete_req_header(original, "content-length"),
          put_req_header(original, "content-type", "multipart/form-data; boundary=x"),
          put_req_header(original, "transfer-encoding", "chunked"),
          put_req_header(original, "x-http-method-override", "PUT"),
          %{
            original
            | req_headers: [{"content-type", "application/json"} | original.req_headers]
          },
          put_req_header(original, "x_bad", "ambiguous")
        ] do
      assert {:replay, _} = Input.select(changed, :login)
    end

    boundary = String.duplicate(" ", 16_382) <> "{}"
    assert {:ok, %{}} = Input.select(conn(boundary, "application/json"), :login)
    assert {:replay, _} = Input.select(conn(boundary <> " ", "application/json"), :login)
  end

  defp conn(body, type) do
    Plug.Test.conn("POST", "/api/v1/auth/login", body)
    |> put_req_header("content-type", type)
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> put_private(:dawarich_raw_body, body)
  end
end
