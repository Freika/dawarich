defmodule DawarichWeb.Api.NotesEndpointTest do
  use Dawarich.ApiEndpointCase

  @moduletag :capture_log
  @key "a4rest-notes-inactive-synthetic"

  setup do
    owner = user!(%{status: 0, api_key: @key, settings: %{"timezone" => "UTC"}})
    %{owner: owner}
  end

  @tag :notes_active
  test "notes CRUD uses inherited API auth without active restriction", ctx do
    assert {200, headers, "[]"} = send_request(ctx, "GET", "/api/v1/notes")
    assert values(headers, "x-dawarich-response") == ["Hey, I'm alive and authenticated!"]

    assert {201, _, body} =
             send_request(ctx, "POST", "/api/v1/notes", %{
               "note" => %{"body" => "Synthetic created", "noted_at" => "2026-09-02T12:00:00Z"}
             })

    id = Jason.decode!(body)["id"]
    path = "/api/v1/notes/#{id}"
    assert {200, _, _} = send_request(ctx, "GET", path)

    for method <- ["PATCH", "PUT"],
        do:
          assert({200, _, _} = send_request(ctx, method, path, %{"note" => %{"title" => method}}))

    assert {200, _, ~s({"message":"Note was successfully deleted"})} =
             send_request(ctx, "DELETE", path)

    assert {404, _, ~s({"error":"Record not found"})} = send_request(ctx, "GET", path)
    no_upstream!(ctx.upstream)
  end

  @tag :notes_replay
  test "notes rollback and unsupported body reach Rails without writes", ctx do
    Repo.query!(
      "INSERT INTO notes (id,user_id,body,noted_at,created_at,updated_at) VALUES (952201,$1,'Untouched',NOW(),NOW(),NOW())",
      [ctx.owner]
    )

    before = Repo.query!("SELECT row_to_json(n)::text FROM notes n").rows

    for {target, body, headers, slices, hosted} <- [
          {"/api/v1/notes", %{"body" => "Rootless"}, [], "", "true"},
          {"/api/v1/notes", %{"note" => %{}}, [], "", "true"},
          {"/api/v1/notes", %{"note" => %{"body" => %{"nested" => "shape"}}}, [], "", "true"},
          {"/api/v1/notes", %{"note" => %{"body" => "No write"}}, [], "api_notes", "true"},
          {"/api/v1/notes", %{"note" => %{"body" => "No write"}}, [], "", "false"},
          {"/api/v1/notes", %{"note" => %{"body" => "No write"}},
           [{"X-HTTP-Method-Override", "PATCH"}], "", "true"}
        ] do
      System.put_env("DAWARICH_RAILS_SLICES", slices)
      System.put_env("SELF_HOSTED", hosted)
      encoded = Jason.encode!(body)
      client = submit(ctx, "POST", target, encoded, headers)
      puma = accept(ctx.upstream)
      {head, rest} = read_head(puma)
      assert request_line(head) == "POST #{target} HTTP/1.1"
      assert read_at_least(puma, rest, byte_size(encoded)) == encoded
      reply(puma, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nrails")
      assert {200, _, "rails"} = read_response(client)
      assert Repo.query!("SELECT row_to_json(n)::text FROM notes n").rows == before
    end
  end

  defp send_request(ctx, method, target, body \\ nil),
    do:
      ctx
      |> submit(method, target, if(body, do: Jason.encode!(body), else: ""), [])
      |> read_response()

  defp submit(ctx, method, target, body, headers) do
    client = connect(ctx.port)

    send_raw(client, [
      "#{method} #{target} HTTP/1.1\r\nHost: localhost\r\nAccept: application/json\r\nAuthorization: Bearer #{@key}\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(body)}\r\n",
      Enum.map(headers, fn {name, value} -> "#{name}: #{value}\r\n" end),
      "\r\n",
      body
    ])

    client
  end
end
