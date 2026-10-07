defmodule Dawarich.Imports.AcceptedDisposition do
  @moduledoc false
  alias Dawarich.Imports.{ImportMessages, Progress}
  alias Dawarich.Jobs.Processed

  def call(repo, args, kind, fallback) do
    if Dawarich.Standalone.enabled?() do
      fail!(repo, args, kind)
    else
      repo.query!(
        "INSERT INTO phoenix.import_handoffs(event_id,import_id,user_id,time_zone,native_fallback) VALUES ($1,$2,$3,$4,$5) ON CONFLICT(event_id) DO NOTHING",
        [
          Ecto.UUID.dump!(args["event_id"]),
          args["import_id"],
          args["user_id"],
          args["time_zone"],
          fallback
        ],
        log: false
      )

      Dawarich.RailsCommands.insert!(repo, kind, args)
      Processed.mark!(repo, args["event_id"], kind <> ".handback")
    end
  end

  defp fail!(repo, args, kind) do
    [[name, settings]] =
      repo.query!(
        "SELECT i.name,u.settings FROM imports i JOIN users u ON u.id=i.user_id WHERE i.id=$1 AND i.user_id=$2",
        [args["import_id"], args["user_id"]],
        log: false
      ).rows

    import = %{id: args["import_id"], user_id: args["user_id"], name: name}
    now = DateTime.utc_now()

    context = %{
      locale: Dawarich.Mail.ExploreFeatures.locale(settings, nil) || "en",
      self_hosted?: Dawarich.ReleaseMigration.self_hosted?()
    }

    error = %ArgumentError{message: "Import cannot be processed natively"}
    message = ImportMessages.failure(import, context, error)

    repo.query!(
      "UPDATE imports SET status=3,error_message=$2,updated_at=$3 WHERE id=$1",
      [import.id, error.message, DateTime.to_naive(now)],
      log: false
    )

    Progress.publish!(repo, import, context.locale)

    Dawarich.Notifications.create!(
      repo,
      import.user_id,
      message.kind,
      message.title,
      message.content,
      DateTime.to_naive(now)
    )

    Processed.mark!(repo, args["event_id"], kind <> ".failed")
  end
end
