defmodule Dawarich.Photos.ProviderVerificationTest do
  use ExUnit.Case, async: false
  import Dawarich.Test.RawHTTP
  alias Dawarich.{Repo, Redis}
  alias Dawarich.Immich.VerifyWorker

  @cap 32 * 1024 * 1024
  @key "synthetic-verification-credential"
  @body ~s({"exifInfo":{"latitude":1,"longitude":2}})
  @paths [
    :worker,
    :immich_check,
    :thumbnail_check,
    :photoprism_check,
    :immich_import,
    :photoprism_import
  ]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Dawarich.ApiEndpointCase.clear_transport_env()
    start_supervised!(hd(Redis.child_specs()))

    [[user]] =
      Repo.query!(
        "INSERT INTO users(email,encrypted_password,settings,created_at,updated_at) VALUES($1,'','{}',NOW(),NOW()) RETURNING id",
        ["verification-#{Ecto.UUID.generate()}@example.test"]
      ).rows

    [[notice]] =
      Repo.query!(
        "INSERT INTO notifications(user_id,title,content,kind,created_at,updated_at) VALUES($1,'Checking','Pending',0,NOW(),NOW()) RETURNING id",
        [user]
      ).rows

    for provider <- ~w(immich photoprism),
        do: Dawarich.Jobs.Ownership.put!(Repo, "command:imports.#{provider}_geodata", :oban)

    %{user: user, notice: notice}
  end

  @tag :verification_redirect
  test "verification worker refuses cross-host redirects without forwarding its Immich key",
       ctx do
    {destination, target, ref} = provider(fn socket -> response(socket, @body) end)

    {base, origin, _} =
      provider(fn socket ->
        reply(
          socket,
          "HTTP/1.1 302 Found\r\nContent-Length: 0\r\nLocation: #{String.replace(destination, "127.0.0.1", "localhost")}/foreign\r\n\r\n"
        )
      end)

    run(:worker, ctx, base)
    Task.await(origin)
    Task.shutdown(target, :brutal_kill)
    refute_received {^ref, :contacted, _}
    assert_unconfirmed(ctx)

    {base, task, _} = provider(fn socket -> response(socket, @body) end)
    run(:worker, ctx, base <> "/provider")
    {head, _} = Task.await(task)
    assert request_line(head) == "GET /provider/api/assets/asset HTTP/1.1"
    assert header(head, "x-api-key") == [@key]
    assert [[0]] = Repo.query!("SELECT kind FROM notifications WHERE id=$1", [ctx.notice]).rows
  end

  @tag :verification_cap
  test "verification and integration clients cancel oversized valid JSON before its terminator",
       ctx do
    for path <- @paths do
      {base, task, _} =
        provider(
          fn socket ->
            reply(
              socket,
              "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nTransfer-Encoding: chunked\r\n\r\n"
            )

            prefix = valid_body(path)
            reply(socket, [Integer.to_string(byte_size(prefix), 16), "\r\n", prefix, "\r\n"])
            chunk = String.duplicate(" ", 64 * 1024)

            Enum.reduce_while(1..div(@cap, byte_size(chunk)), :ok, fn _, _ ->
              case :gen_tcp.send(socket, ["10000\r\n", chunk, "\r\n"]) do
                :ok -> {:cont, :ok}
                {:error, _} -> {:halt, :closed}
              end
            end)

            early = :gen_tcp.recv(socket, 0, 1000)
            :gen_tcp.send(socket, "0\r\n\r\n")
            early
          end,
          path == :thumbnail_check
        )

      result = run(path, ctx, base)
      assert {_, {:error, :closed}} = Task.await(task), "#{path} buffered the oversized body"
      if path == :worker, do: assert_unconfirmed(ctx), else: assert(match?({:error, _}, result))
    end
  end

  @tag :verification_url
  test "verification and integration clients reject malformed bases instead of confirming the root",
       ctx do
    for path <- @paths, suffix <- ["?misconfigured=1", "#fragment", "/../root", "/"] do
      {base, task, ref} = provider(fn socket -> response(socket, valid_body(path)) end)
      result = run(path, ctx, base <> suffix)
      Task.shutdown(task, :brutal_kill)
      refute_received {^ref, :contacted, _}, "#{path} fetched a malformed provider URL"
      if path == :worker, do: assert_unconfirmed(ctx), else: assert(match?({:error, _}, result))
    end
  end

  defp run(path, ctx, base) do
    source = if path in [:photoprism_check, :photoprism_import], do: "photoprism", else: "immich"
    settings = %{(source <> "_url") => base, (source <> "_api_key") => @key}
    Repo.query!("UPDATE users SET settings=$2 WHERE id=$1", [ctx.user, settings])

    case path do
      :worker ->
        args = %{
          "notification_id" => ctx.notice,
          "assets" => [%{"immich_asset_id" => "asset", "latitude" => 1, "longitude" => 2}],
          "immich_url" => base,
          "pass" => 3,
          "confirmed" => 0,
          "unconfirmed" => [],
          "event_id" => Ecto.UUID.generate()
        }

        assert :ok = VerifyWorker.run(Repo, Oban, args)

      path when path in [:immich_check, :thumbnail_check, :photoprism_check] ->
        Dawarich.Settings.Integrations.Connection.test(source, settings, "en")

      _ ->
        module =
          if source == "immich",
            do: Dawarich.Imports.Integrations.Immich,
            else: Dawarich.Imports.Integrations.Photoprism

        module.run(Repo, %{
          "user_id" => ctx.user,
          "time_zone" => "UTC",
          "event_id" => Ecto.UUID.generate()
        })
    end
  end

  defp assert_unconfirmed(ctx) do
    assert [[1, content]] =
             Repo.query!("SELECT kind,content FROM notifications WHERE id=$1", [ctx.notice]).rows

    assert content =~ "Location updates still unconfirmed: 1"
  end

  defp valid_body(:worker), do: @body
  defp valid_body(path) when path in [:photoprism_check, :photoprism_import], do: "[]"
  defp valid_body(_), do: ~s({"assets":{"items":[]}})

  defp provider(fun, thumbnail \\ false) do
    server = listen()
    on_exit(fn -> :gen_tcp.close(server.listen) end)
    parent = self()
    ref = make_ref()

    task =
      Task.async(fn ->
        if thumbnail do
          socket = accept(server)
          read_request(socket)
          response(socket, ~s({"assets":{"items":[{"id":"asset"}]}}))
          :gen_tcp.close(socket)
        end

        socket = accept(server)
        head = read_request(socket)
        send(parent, {ref, :contacted, head})
        result = fun.(socket)
        :gen_tcp.close(socket)
        {head, result}
      end)

    {"http://127.0.0.1:#{server.port}", task, ref}
  end

  defp read_request(socket) do
    {head, rest} = read_head(socket)
    size = head |> header("content-length") |> List.first() || "0"
    read_at_least(socket, rest, String.to_integer(size))
    head
  end

  defp response(socket, body),
    do:
      reply(socket, [
        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: #{byte_size(body)}\r\n\r\n",
        body
      ])
end
