defmodule Dawarich.UserData.Restore.Resume do
  @moduledoc false
  alias Dawarich.UserData.Restore.Files
  alias Dawarich.Imports.LeaseLost

  def call(repo, directory, %{restore_run: run} = context, fun) do
    [[saved]] =
      repo.query!(
        "SELECT attachment_snapshot FROM phoenix.import_runs WHERE import_id=$1 AND event_id=$2 FOR UPDATE",
        [run.import_id, Ecto.UUID.dump!(run.event_id)],
        log: false
      ).rows

    case saved do
      nil ->
        stats = fun.()

        snapshot = %{
          "attachment" => run.attachment,
          "restore" => %{"stats" => stats, "uploads" => Files.manifest(context)}
        }

        repo.query!(
          "UPDATE phoenix.import_runs SET attachment_snapshot=$2,updated_at=now() WHERE import_id=$1",
          [run.import_id, snapshot],
          log: false
        )

        stats

      %{"attachment" => attachment, "restore" => %{"stats" => stats, "uploads" => uploads}} ->
        unless attachment == run.attachment, do: raise(LeaseLost)
        Files.resume(uploads, directory, context)
        stats

      _ ->
        raise LeaseLost
    end
  end

  def call(_repo, _directory, _context, fun), do: fun.()
end
