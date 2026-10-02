defmodule Dawarich.Imports.DestroyLegacySchemaTest do
  use Dawarich.IngestCase
  alias Dawarich.Imports.Destroy
  alias Dawarich.Jobs.Ownership

  @destroy_sql Path.expand(
                 "../../../priv/repo/sql/20261001170000_import_destroy_runs.sql",
                 __DIR__
               )

  setup do
    Repo.query!(File.read!(@destroy_sql), [], query_type: :text)
    :ok
  end

  test "Sidekiq deletion and its explicit retry do not require the native Oban table" do
    Repo.query!("DROP SCHEMA IF EXISTS oban CASCADE", [], log: false)
    assert [[nil]] = Repo.query!("SELECT to_regclass('oban.oban_jobs')", [], log: false).rows
    user = user!()

    [[id]] =
      Repo.query!(
        "INSERT INTO imports(user_id,name,source,status,created_at,updated_at) VALUES($1,'legacy-delete.csv',10,4,now(),now()) RETURNING id",
        [user],
        log: false
      ).rows

    Ownership.put!(Repo, "command:imports.destroy", :sidekiq)
    assert {:ok, :queued} = Destroy.enqueue(Repo, user, id, %{zone: "UTC", locale: "en"})
    assert {:ok, :queued} = Destroy.enqueue(Repo, user, id, %{zone: "UTC", locale: "en"})

    assert [["imports.destroy_requested", 1]] =
             Repo.query!(
               "SELECT kind,count(*) FROM phoenix.rails_commands GROUP BY kind",
               [],
               log: false
             ).rows
  end
end
