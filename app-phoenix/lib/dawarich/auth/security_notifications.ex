defmodule Dawarich.Auth.SecurityNotifications do
  @moduledoc false

  def ready?(context, changes) do
    not required?(context, changes) or is_function(context[:enqueue_security_notification], 1)
  end

  def enqueue(repo, previous, current, changes, context) do
    if required?(context, changes) do
      intents =
        []
        |> add(Map.has_key?(changes, :encrypted_password), :password_change, current.email)
        |> add(Map.has_key?(changes, :email), :email_changed, previous.email)

      Enum.each(intents, fn {kind, recipient} ->
        intent = %{
          kind: kind,
          user_id: current.id,
          recipient: recipient,
          resource_email: current.email,
          locale: Map.get(context, :locale, "en")
        }

        if context.enqueue_security_notification.(intent) != :ok,
          do: repo.rollback(:notification_owner)
      end)
    end

    :ok
  end

  defp required?(context, changes),
    do:
      Map.get(context, :self_hosted, System.get_env("SELF_HOSTED", "true") != "false") == false and
        (Map.has_key?(changes, :encrypted_password) or Map.has_key?(changes, :email))

  defp add(intents, true, kind, recipient), do: intents ++ [{kind, recipient}]
  defp add(intents, false, _, _), do: intents
end
