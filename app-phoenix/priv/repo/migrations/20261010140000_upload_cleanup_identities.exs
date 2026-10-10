defmodule Dawarich.Repo.Migrations.UploadCleanupIdentities do
  use Ecto.Migration

  def up do
    alter table(:native_uploads, prefix: "phoenix") do
      add :object_key, :text
      add :service_name, :text
      add :cleanup_at, :utc_datetime_usec
    end

    execute "UPDATE phoenix.native_uploads SET cleanup_at=timezone('UTC',now()) WHERE state IN ('cancelled','expired')"

    create index(:native_uploads, [:cleanup_at],
             prefix: "phoenix",
             where: "cleanup_at IS NOT NULL"
           )
  end

  def down do
    drop index(:native_uploads, [:cleanup_at], prefix: "phoenix")

    alter table(:native_uploads, prefix: "phoenix") do
      remove :object_key
      remove :service_name
      remove :cleanup_at
    end
  end
end
