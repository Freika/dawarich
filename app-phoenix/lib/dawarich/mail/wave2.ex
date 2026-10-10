defmodule Dawarich.Mail.Wave2 do
  @moduledoc false
  require EEx

  alias Dawarich.I18n
  alias Dawarich.Mail.{Delivery, ExploreFeatures, Layout, Recipient}
  alias Dawarich.ReleaseMigration

  @dir Path.expand("../../../priv/mail", __DIR__)

  @surfaces %{
    welcome: {"users_mailer.welcome", "mailers.users.welcome.subject"},
    archival_approaching:
      {"users_mailer.archival_approaching", "mailers.users.archival_approaching.subject"},
    oauth_account_link:
      {"users_mailer.oauth_account_link", "mailers.users.oauth_account_link.subject"},
    account_destroy_confirmation:
      {"users_mailer.account_destroy_confirmation",
       "mailers.users.account_destroy_confirmation.subject"},
    family_invitation: {"family_mailer.invitation", "mailers.family.invitation.subject"},
    family_lapse: {"family_mailer.plan_lapsed", "mailers.family.plan_lapsed.subject"}
  }

  @utm "&utm_source=email&utm_medium=email&utm_campaign=archival_approaching&utm_content=upgrade"

  @link_url "SELECT payload->>'link_url' FROM public.job_outbox WHERE event_id = $1"

  for surface <- Map.keys(@surfaces), format <- [:html, :text] do
    file = Path.join(@dir, "wave2/#{surface}.#{format}.eex")
    @external_resource file
    compiled = EEx.compile_file(file)

    defp body(unquote(surface), unquote(format), unquote({:assigns, [], nil})),
      do: unquote(compiled)
  end

  def welcome(user, locale, env),
    do: build(:welcome, user.email, locale, %{email: user.email}, %{}, env)

  def archival_approaching(
        user_id,
        user,
        locale,
        env,
        now_unix \\ System.os_time(:second),
        jti \\ Ecto.UUID.generate()
      ) do
    case env["JWT_SECRET_KEY"] do
      nil ->
        {:error, "JWT_SECRET_KEY is not set"}

      secret ->
        token = subscription_token(user_id, user.email, secret, now_unix, jti)
        url = "#{manager_url(env)}/auth/dawarich?token=#{token}" <> @utm
        assigns = %{email: user.email, upgrade_url: url}
        build(:archival_approaching, user.email, locale, assigns, %{}, env)
    end
  end

  def oauth_account_link(user, locale, provider_label, link_url, env) do
    assigns = %{email: user.email, provider_label: provider_label, link_url: link_url}
    build(:oauth_account_link, user.email, locale, assigns, %{"provider" => provider_label}, env)
  end

  def account_destroy_confirmation(user, locale, link_url, env) do
    assigns = %{email: user.email, link_url: link_url}
    build(:account_destroy_confirmation, user.email, locale, assigns, %{}, env)
  end

  def family_invitation(to, locale, token, family, inviter_email, env) do
    with {:ok, base_url} <- base_url(env) do
      assigns = %{
        family: family,
        inviter_email: inviter_email,
        accept_url: base_url <> "/family/invitations/" <> token
      }

      build(:family_invitation, to, locale, assigns, %{"family" => family}, env)
    end
  end

  def family_lapse(email, locale, family, owner_email, env) do
    subscription_url =
      if ReleaseMigration.self_hosted?(), do: nil, else: "#{manager_url(env)}/auth/dawarich"

    assigns = %{
      email: email,
      family: family,
      owner_email: owner_email,
      subscription_url: subscription_url
    }

    build(:family_lapse, email, locale, assigns, %{"family" => family}, env)
  end

  def render(surface, locale, assigns, subject_bindings \\ %{}) do
    {scope, subject} = Map.fetch!(@surfaces, surface)
    t = fn key, bindings -> text!(locale, scope <> "." <> key, bindings) end
    escaped = &Map.new(&1, fn {key, value} -> {key, h(value)} end)
    html = Map.merge(assigns, %{t: &h(t.(&1, %{})), th: &t.(&1, escaped.(&2))})
    text = Map.merge(assigns, %{t: &t.(&1, %{}), th: t})

    %{
      subject: text!(locale, subject, subject_bindings),
      html: Layout.html(locale, body(surface, :html, html)),
      text: Layout.text(body(surface, :text, text))
    }
  end

  def base_url(env) do
    case env["DOMAIN"] do
      domain when domain in [nil, ""] ->
        {:error, "DOMAIN is not set"}

      domain ->
        {:ok, if(env["RAILS_ENV"] == "staging", do: "http://", else: "https://") <> domain}
    end
  end

  def manager_url(env), do: if(ReleaseMigration.self_hosted?(), do: nil, else: env["MANAGER_URL"])

  def subscription_token(user_id, email, secret, now_unix, jti \\ Ecto.UUID.generate()) do
    header = Jason.encode!(%Jason.OrderedObject{values: [{"alg", "HS256"}]})

    payload =
      Jason.encode!(%Jason.OrderedObject{
        values: [
          {"user_id", user_id},
          {"email", email},
          {"purpose", "checkout"},
          {"jti", jti},
          {"exp", now_unix + 1800}
        ]
      })

    input = b64(header) <> "." <> b64(payload)
    input <> "." <> b64(:crypto.mac(:hmac, :sha256, secret, input))
  end

  def decode(1, payload, spec) when is_map(payload) do
    if map_size(payload) == map_size(spec) and
         Enum.all?(spec, fn {key, type} -> type?(Map.get(payload, key), type) end),
       do: {:ok, payload},
       else: {:error, "invalid_payload"}
  end

  def decode(1, _payload, _spec), do: {:error, "invalid_payload"}
  def decode(_version, _payload, _spec), do: {:error, "unsupported_version"}

  def deliver_to_user(repo, handler, key, args, build) do
    case Recipient.fetch(repo, args["user_id"]) do
      nil ->
        :ok

      user ->
        locale = ExploreFeatures.locale(Dawarich.UserSettings.get(user), args["locale"])

        record = NaiveDateTime.to_iso8601(user.created_at)

        Delivery.deliver(repo, handler, key, record, args["event_id"], fn ->
          build.(user, locale, System.get_env())
        end)
    end
  end

  def link_url(repo, %{"event_id" => event_id} = args) do
    if args["link_expires_at"] <= System.os_time(:second) do
      :ok
    else
      case repo.query!(@link_url, [Ecto.UUID.dump!(event_id)], log: false).rows do
        [[url]] when is_binary(url) ->
          if token_digest(url) == args["link_token_sha256"],
            do: {:ok, url},
            else: {:cancel, "link digest mismatch"}

        _ ->
          :ok
      end
    end
  end

  defp token_digest(url) do
    case URI.decode_query(URI.parse(url).query || "") do
      %{"token" => token} -> Base.encode16(:crypto.hash(:sha256, token), case: :lower)
      _ -> nil
    end
  end

  defp build(surface, to, locale, assigns, subject_bindings, env) do
    message = render(surface, locale, assigns, subject_bindings)
    {:ok, Map.merge(message, %{from: env["SMTP_FROM"], to: to})}
  end

  defp type?(value, :integer), do: is_integer(value)
  defp type?(value, :string), do: is_binary(value)

  defp h(value), do: ExploreFeatures.h(value)

  defp b64(binary), do: Base.url_encode64(binary, padding: false)

  defp text!(locale, key, bindings) do
    case I18n.t(locale, key, bindings) do
      {:ok, text} when is_binary(text) -> text
      other -> raise "no translation for #{locale}.#{key}: #{inspect(other)}"
    end
  end
end
