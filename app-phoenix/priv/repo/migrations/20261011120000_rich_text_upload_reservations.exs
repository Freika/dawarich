defmodule Dawarich.Repo.Migrations.RichTextUploadReservations do
  use Ecto.Migration

  def up do
    drop constraint(:native_uploads, :native_upload_states, prefix: "phoenix")

    create constraint(:native_uploads, :native_upload_states,
             prefix: "phoenix",
             check:
               "state IN ('pending','claimed','cancelled','expired','purged') AND kind IN ('imports','account','rich_text') AND (original_size > 0 OR (kind='rich_text' AND original_size=0))"
           )

    create index(:native_uploads, [:expires_at],
             prefix: "phoenix",
             name: :native_rich_orphan_deadline,
             where: "kind='rich_text' AND state='claimed'"
           )
  end

  def down do
    drop index(:native_uploads, [:expires_at],
           prefix: "phoenix",
           name: :native_rich_orphan_deadline
         )

    drop constraint(:native_uploads, :native_upload_states, prefix: "phoenix")

    create constraint(:native_uploads, :native_upload_states,
             prefix: "phoenix",
             check:
               "state IN ('pending','claimed','cancelled','expired','purged') AND kind IN ('imports','account') AND original_size > 0"
           )
  end
end
