defmodule Dawarich.Repo.Migrations.NativeUploadLifecycle do
  use Ecto.Migration

  def change do
    create table(:native_uploads, primary_key: false, prefix: "phoenix") do
      add :reference, :text, primary_key: true
      add :user_id, :bigint, null: false

      add :blob_id,
          references(:active_storage_blobs,
            type: :bigint,
            prefix: "public",
            on_delete: :nilify_all
          )

      add :kind, :text, null: false
      add :state, :text, null: false, default: "pending"
      add :original_filename, :text, null: false
      add :original_size, :bigint, null: false
      add :client_wrapped, :boolean, null: false, default: false
      add :expires_at, :utc_datetime_usec, null: false
      add :target_until, :utc_datetime_usec
      add :created_at, :utc_datetime_usec, null: false
    end

    create index(:native_uploads, [:user_id, :state], prefix: "phoenix")
    create index(:native_uploads, [:expires_at], prefix: "phoenix", where: "state='pending'")

    create constraint(:native_uploads, :native_upload_states,
             prefix: "phoenix",
             check:
               "state IN ('pending','claimed','cancelled','expired','purged') AND kind IN ('imports','account') AND original_size > 0"
           )
  end
end
