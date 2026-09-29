defmodule Dawarich.AppVersion.CheckWorkerTest do
  use Dawarich.JobsCase
  use Oban.Testing, repo: Dawarich.ScratchRepo

  alias Dawarich.AppVersion.CheckWorker
  alias Dawarich.Jobs.Ownership

  @key "cron:app_version_checking_job"

  setup do
    dir = Path.join(System.tmp_dir!(), "a1-tags-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "repos/Freika/dawarich"))

    {:ok, httpd} =
      :inets.start(:httpd,
        port: 0,
        bind_address: {127, 0, 0, 1},
        server_name: ~c"localhost",
        server_root: to_charlist(dir),
        document_root: to_charlist(dir)
      )

    port = :httpd.info(httpd)[:port]
    previous_env = System.get_env("RAILS_ENV")
    System.put_env("RAILS_ENV", "staging")

    Application.put_env(
      :dawarich,
      :app_version_url,
      "http://127.0.0.1:#{port}/repos/Freika/dawarich/tags"
    )

    on_exit(fn ->
      :inets.stop(:httpd, httpd)
      File.rm_rf!(dir)
      Application.delete_env(:dawarich, :app_version_url)

      if previous_env,
        do: System.put_env("RAILS_ENV", previous_env),
        else: System.delete_env("RAILS_ENV")
    end)

    %{tags: Path.join(dir, "repos/Freika/dawarich/tags")}
  end

  defp stored, do: rows("SELECT latest_version FROM phoenix.app_version")

  test "stores the newest release tag while Oban owns the entry", %{tags: tags} do
    File.write!(tags, ~s([{"name":"nightly"},{"name":"1.16.0"},{"name":"1.15.9"}]))
    :ok = Ownership.put!(ScratchRepo, @key, :oban)

    assert perform_job(CheckWorker, %{}) == :ok
    assert stored() == [["1.16.0"]]
  end

  test "is cancelled as not_owner while Sidekiq owns the entry, writing nothing", %{tags: tags} do
    File.write!(tags, ~s([{"name":"1.16.0"}]))

    assert perform_job(CheckWorker, %{}) == {:cancel, :not_owner}
    assert stored() == []
  end

  test "a failed fetch keeps the previous row" do
    :ok = Ownership.put!(ScratchRepo, @key, :oban)

    rows(
      "INSERT INTO phoenix.app_version (latest_version, checked_at) VALUES ('1.15.0', now() - interval '1 hour')"
    )

    assert perform_job(CheckWorker, %{}) == :ok
    assert stored() == [["1.15.0"]]
  end

  test "stores the running version when no tag is a release", %{tags: tags} do
    File.write!(tags, ~s([{"name":"nightly"}]))
    :ok = Ownership.put!(ScratchRepo, @key, :oban)

    running =
      :dawarich |> Application.fetch_env!(:app_version_file) |> File.read!() |> String.trim()

    assert perform_job(CheckWorker, %{}) == :ok
    assert stored() == [[running]]
  end

  test "does nothing in production, like Rails", %{tags: tags} do
    File.write!(tags, ~s([{"name":"1.16.0"}]))
    :ok = Ownership.put!(ScratchRepo, @key, :oban)
    System.put_env("RAILS_ENV", "production")

    assert perform_job(CheckWorker, %{}) == :ok
    assert stored() == []
  end
end
