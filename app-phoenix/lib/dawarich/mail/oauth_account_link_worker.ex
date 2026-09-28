defmodule Dawarich.Mail.OauthAccountLinkWorker do
  @moduledoc false
  use Oban.Worker, queue: :mailers, max_attempts: 20

  alias Dawarich.Mail.Wave2

  @handler "mail.user.oauth_account_link"
  @payload %{
    "user_id" => :integer,
    "locale" => :string,
    "provider_label" => :string,
    "link_url" => :string,
    "link_token_sha256" => :string,
    "link_expires_at" => :integer
  }

  def args_from_command(version, payload) do
    with {:ok, args} <- Wave2.decode(version, payload, @payload),
         do: {:ok, Map.delete(args, "link_url")}
  end

  def provider_key(%{"user_id" => user_id, "link_token_sha256" => digest}),
    do: "oauth-link:#{user_id}:#{digest}"

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    repo = Dawarich.Jobs.repo()

    with {:ok, url} <- Wave2.link_url(repo, args) do
      Wave2.deliver_to_user(repo, @handler, provider_key(args), args, fn user, locale, env ->
        Wave2.oauth_account_link(user, locale, args["provider_label"], url, env)
      end)
    end
  end
end
