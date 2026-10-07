Mix.Task.run("app.config")
repo = Application.fetch_env!(:dawarich, Dawarich.Repo)

Application.put_env(
  :dawarich,
  Dawarich.Repo,
  Keyword.put(repo, :database, System.fetch_env!("DATABASE_NAME"))
)

{:ok, _} = Application.ensure_all_started(:ecto_sql)
{:ok, _} = Dawarich.Repo.start_link()
Dawarich.Repo.query!("CREATE SCHEMA IF NOT EXISTS oban", [], log: false)

Ecto.Migrator.run(Dawarich.Repo, Path.expand("../../priv/repo/oban_migrations", __DIR__), :up,
  all: true,
  prefix: "oban",
  log: false
)

Dawarich.Repo.stop()
{:ok, _} = Application.ensure_all_started(:dawarich)

defmodule S02CoexistenceProvider do
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, _) do
    {:ok, body, conn} = read_body(conn)

    items =
      if Jason.decode!(body)["page"] == 1 do
        [
          %{
            "id" => "public-0",
            "type" => "IMAGE",
            "fileCreatedAt" => "2026-03-29T00:30:00Z",
            "exifInfo" => %{"latitude" => "52.5", "longitude" => "13.4"}
          }
        ]
      else
        []
      end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{assets: %{items: items}}))
  end
end

Application.put_env(:dawarich, :allowed_hosts, [])

Application.put_env(
  :dawarich,
  :rails_upstream,
  {{127, 0, 0, 1}, String.to_integer(System.fetch_env!("S02_UPSTREAM_PORT"))}
)

System.delete_env("DAWARICH_RAILS")
System.put_env("SELF_HOSTED", "true")
System.put_env("DAWARICH_RAILS_SLICES", "api_shared")
{:ok, cache} = Supervisor.start_link(Dawarich.Redis.cache_child_specs(), strategy: :one_for_one)
{:ok, provider} = Bandit.start_link(plug: S02CoexistenceProvider, ip: {127, 0, 0, 1}, port: 0)
{:ok, endpoint} = Bandit.start_link(plug: DawarichWeb.Endpoint, ip: {127, 0, 0, 1}, port: 0)
{:ok, {_, provider_port}} = ThousandIsland.listener_info(provider)
{:ok, {_, endpoint_port}} = ThousandIsland.listener_info(endpoint)

File.write!(
  System.fetch_env!("S02_PORT_FILE"),
  Jason.encode!(%{provider: provider_port, endpoint: endpoint_port})
)

IO.gets("")
Enum.each([endpoint, provider, cache], &Supervisor.stop/1)
