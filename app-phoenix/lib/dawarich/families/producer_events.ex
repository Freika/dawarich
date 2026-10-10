defmodule Dawarich.Families.ProducerEvents do
  @moduledoc false
  alias Dawarich.Families.{Events, Expirations, Sharing}

  def api(repo, user, kind, now, action, effect) do
    {:ok, result} =
      repo.transaction(fn ->
        result = effect.()

        case result do
          {:ok, status, _} when status in [200, 201] ->
            case repo.query!("SELECT family_id FROM family_memberships WHERE user_id=$1", [user],
                   log: false
                 ).rows do
              [[id]] ->
                family(repo, id, kind, now, action, value(repo, user, action, result), user)

              [] ->
                :ok
            end

          _ ->
            :ok
        end

        result
      end)

    result
  end

  def family(repo, family, kind, now, action \\ nil, value \\ nil, actor \\ nil) do
    recipients = recipients(repo, family)
    Events.enqueue(repo, recipients, kind)
    ctx = %{now: now, self_hosted: Dawarich.ReleaseMigration.self_hosted?()}
    Expirations.enqueue(repo, family, actor, recipients, action, value, ctx)
  end

  def recipients(repo, family) do
    repo.query!("SELECT user_id FROM family_memberships WHERE family_id=$1", [family], log: false).rows
    |> List.flatten()
  end

  defp value(repo, user, :set_sharing, _) do
    [[settings]] = repo.query!("SELECT settings FROM users WHERE id=$1", [user], log: false).rows
    Sharing.config(settings)
  end

  defp value(_, _, _, result) do
    case Dawarich.Families.NativeCommandDispatch.result(result) do
      {:ok, value} -> value
      _ -> nil
    end
  end
end
