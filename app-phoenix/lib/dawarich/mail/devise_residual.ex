defmodule Dawarich.Mail.DeviseResidual do
  @moduledoc false
  require EEx

  alias Dawarich.I18n
  alias Dawarich.Mail.ExploreFeatures

  @dir Path.expand("../../../priv/mail/devise", __DIR__)
  @surfaces [:email_changed, :password_change]

  for surface <- @surfaces do
    file = Path.join(@dir, "#{surface}.html.eex")
    @external_resource file
    compiled = EEx.compile_file(file)

    defp body(unquote(surface), unquote({:assigns, [], nil})), do: unquote(compiled)
  end

  def message(surface, recipient, resource_email, locale, env) when surface in @surfaces do
    scope = "devise.mailer.#{surface}."
    t = &(text!(locale, scope <> &1) |> ExploreFeatures.h())

    assigns = %{
      recipient: recipient,
      resource_email: resource_email,
      t: t,
      h: &ExploreFeatures.h/1
    }

    %{
      from: env["SMTP_FROM"],
      reply_to: env["SMTP_FROM"],
      to: recipient,
      subject: text!(locale, scope <> "subject"),
      html: body(surface, assigns),
      format: :html_only
    }
  end

  defp text!(locale, key) do
    case I18n.t(locale, key) do
      {:ok, text} when is_binary(text) -> text
      _ -> raise "missing Devise residual translation"
    end
  end
end
