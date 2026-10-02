for repo <- [
      Dawarich.Repo,
      Dawarich.ScratchRepo,
      Dawarich.ScratchCaseRepo,
      Dawarich.TracksScratchRepo
    ] do
  config = Application.fetch_env!(:dawarich, repo)

  Application.put_env(
    :dawarich,
    repo,
    config |> Keyword.put(:pool_size, 2) |> Keyword.put(:pool, DBConnection.ConnectionPool)
  )
end

Application.ensure_all_started(:postgrex)
Application.ensure_all_started(:ecto_sql)
Dawarich.Release.migrate()
{:ok, _} = Application.ensure_all_started(:dawarich)
Logger.configure(level: :warning)
Application.put_env(:dawarich, :jobs_repo, Dawarich.Repo)
port = Dawarich.Front.free_loopback_port()
root = Path.expand("..", File.cwd!())

{:ok, _} =
  Dawarich.RailsServer.start_link(
    argv: [
      "bash",
      "-c",
      "cd .. && exec bundle exec puma -b tcp://127.0.0.1:#{port} -t 2:2 app-phoenix/test/support/auth/stand.ru"
    ],
    env: [
      {"RAILS_ENV", "test"},
      {"RACK_ENV", "test"},
      {"BUNDLE_GEMFILE", Path.join(root, "Gemfile")}
    ]
  )

Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, port})

defmodule Dawarich.Auth.Standalone do
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, _) do
    if String.starts_with?(conn.request_path, "/phoenix/js/") do
      DawarichWeb.Endpoint.call(conn, DawarichWeb.Endpoint.init([]))
    else
      DawarichWeb.AuthHandler.call(conn,
        enabled: true,
        registration_enabled: true,
        fallback: &forward/1
      )
    end
  end

  defp forward(conn) do
    if Enum.any?(get_req_header(conn, "accept"), &String.contains?(&1, "text/html")) do
      conn = DawarichWeb.RailsAuth.call(conn, [])
      before = conn.assigns.rails_session
      conn = DawarichWeb.AuthRestore.call(conn, enabled: true)

      conn =
        if before != conn.assigns.rails_session do
          value = conn.resp_cookies["_dawarich_session"].value

          pair =
            Plug.Conn.Cookies.encode("_dawarich_session", %{value: value})
            |> String.split(";", parts: 2)
            |> hd()

          others =
            get_req_header(conn, "cookie")
            |> Enum.join("; ")
            |> String.split("; ")
            |> Enum.reject(&String.starts_with?(&1, "_dawarich_session="))

          put_req_header(conn, "cookie", Enum.join([pair | others], "; "))
        else
          conn
        end

      DawarichWeb.RailsProxy.call(conn, Application.fetch_env!(:dawarich, :rails_upstream))
    else
      DawarichWeb.RailsProxy.call(conn, Application.fetch_env!(:dawarich, :rails_upstream))
    end
  end
end

{:ok, _} = Bandit.start_link(plug: Dawarich.Auth.Standalone, ip: {127, 0, 0, 1}, port: 3175)

File.write!(
  Path.join(root, "auth-http-ready.json"),
  Jason.encode!(%{proxy: 3175, puma: port, beam_pid: System.pid()})
)

Process.sleep(:infinity)
