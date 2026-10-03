defmodule Dawarich.Auth.Recovery.SynchronousBinding do
  @moduledoc false
  alias Dawarich.Auth.Recovery.{Mail, Notification}

  def callback(base_url, env) do
    fn notification, user -> deliver(notification, user, base_url, env) end
  end

  def deliver(
        %Notification{user_id: id} = notification,
        %{id: id, email: email} = user,
        base_url,
        env
      ) do
    locale = DawarichWeb.Locale.resolve(nil, user, %{"locale" => notification.locale})

    with {:ok, message} <-
           Mail.build(notification.kind, email, locale, notification.raw, base_url, env) do
      message |> Map.put(:text, "") |> Dawarich.Mail.Smtp.deliver(env)
    end
  end

  def deliver(_, _, _, _), do: {:error, :snapshot}
end
