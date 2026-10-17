defmodule Dawarich.ObservabilityRetirementTest do
  use Dawarich.JobsCase
  use Oban.Testing, repo: Dawarich.ScratchRepo

  alias Dawarich.AppVersion.CheckWorker
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Test.RawHTTP

  setup do
    original =
      Map.new(
        ~w(POSTHOG_API_KEY POSTHOG_HOST SELF_HOSTED RAILS_ENV APPLICATION_HOSTS),
        &{&1, System.get_env(&1)}
      )

    url = Application.fetch_env(:dawarich, :app_version_url)

    boot =
      Map.new(
        [:rails_upstream, :public_files, :allowed_hosts],
        &{&1, Application.fetch_env(:dawarich, &1)}
      )

    server = RawHTTP.listen()
    parent = self()
    start_supervised!({Task, fn -> serve(server, parent) end})

    System.put_env(%{
      "POSTHOG_API_KEY" => "synthetic-retired-server-key",
      "POSTHOG_HOST" => "http://127.0.0.1:#{server.port}",
      "SELF_HOSTED" => "false",
      "RAILS_ENV" => "staging",
      "APPLICATION_HOSTS" => "www.example.com"
    })

    Application.put_env(:dawarich, :app_version_url, "http://127.0.0.1:#{server.port}/tags")

    on_exit(fn ->
      :gen_tcp.close(server.listen)

      Enum.each(original, fn {key, value} ->
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end)

      case url do
        {:ok, value} -> Application.put_env(:dawarich, :app_version_url, value)
        :error -> Application.delete_env(:dawarich, :app_version_url)
      end

      Application.ensure_all_started(:dawarich)

      Enum.each(boot, fn
        {key, {:ok, value}} -> Application.put_env(:dawarich, key, value)
        {key, :error} -> Application.delete_env(:dawarich, key)
      end)
    end)

    :ok
  end

  test "native boot web and jobs run without server PostHog configuration or emissions" do
    :ok = Application.stop(:dawarich)
    assert {:ok, _} = Application.ensure_all_started(:dawarich)
    assert Process.whereis(Dawarich.Supervisor)
    assert Process.whereis(DawarichWeb.Endpoint)

    response =
      Plug.Test.conn(:get, "/api-docs/v1/swagger.yaml")
      |> then(&%{&1 | req_headers: [{"host", "www.example.com"}]})
      |> DawarichWeb.Endpoint.call(DawarichWeb.Endpoint.init([]))

    assert response.status == 200
    assert response.resp_body == File.read!(Dawarich.RailsRoot.join("swagger/v1/swagger.yaml"))
    :ok = Ownership.put!(ScratchRepo, "cron:app_version_checking_job", :oban)
    assert perform_job(CheckWorker, %{}) == :ok
    assert rows("SELECT latest_version FROM phoenix.app_version") == [["1.15.4"]]
    assert_received :native_job_http
    refute_receive {:posthog_request, _}, 0

    refute Enum.any?(Application.started_applications(), fn {app, _, _} ->
             app |> Atom.to_string() |> String.downcase() |> String.contains?("posthog")
           end)

    refute Enum.any?(Supervisor.which_children(Dawarich.Supervisor), fn {id, _, _, _} ->
             id |> inspect() |> String.downcase() |> String.contains?("posthog")
           end)
  end

  defp serve(server, parent) do
    socket = RawHTTP.accept(server)
    {head, _} = RawHTTP.read_head(socket)
    request = RawHTTP.request_line(head)

    body =
      if request == "GET /tags HTTP/1.1" do
        send(parent, :native_job_http)
        ~s([{"name":"1.15.4"}])
      else
        send(parent, {:posthog_request, request})
        "{}"
      end

    RawHTTP.reply(socket, "HTTP/1.1 200 OK\r\nContent-Length: #{byte_size(body)}\r\n\r\n#{body}")
    :gen_tcp.close(socket)
    serve(server, parent)
  end
end
