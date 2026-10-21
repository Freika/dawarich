defmodule Dawarich.Auth.AccountLink.Mailer do
  @moduledoc false

  def enqueue(payload, repo \\ Dawarich.Repo) do
    result =
      Dawarich.Mail.UserCallbacks.link(
        repo,
        "oauth_account_link",
        payload["user_id"],
        payload["link_url"],
        locale: payload["locale"],
        provider_label: payload["provider_label"]
      )

    case result do
      {:ok, :ok} -> :ok
      _ -> {:error, :mail_owner}
    end
  end
end
