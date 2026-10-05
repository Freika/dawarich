defmodule Dawarich.Mail.Residual do
  @moduledoc false
  require EEx

  alias Dawarich.{I18n, LocalTime}
  alias Dawarich.Mail.{ExploreFeatures, Layout}
  alias DawarichWeb.LocalizedTime

  @dir Path.expand("../../../priv/mail/residual", __DIR__)
  @surfaces %{
    otp_account_locked:
      {"users_mailer.otp_account_locked", "mailers.users.otp_account_locked.subject"},
    test_email: {"users_mailer.test_email", "mailers.users.test_email.subject"},
    location_request:
      {"family_mailer.location_request", "mailers.family.location_request.subject"}
  }

  for {surface, formats} <- [
        otp_account_locked: [:html, :text],
        test_email: [:html],
        location_request: [:html, :text]
      ],
      format <- formats do
    file = Path.join(@dir, "#{surface}.#{format}.eex")
    @external_resource file
    compiled = EEx.compile_file(file)

    defp body(unquote(surface), unquote(format), unquote({:assigns, [], nil})),
      do: unquote(compiled)
  end

  def message(surface, recipient, ambient, env, opts) do
    locale = ExploreFeatures.locale(recipient.settings, ambient)
    assigns = assigns(surface, recipient, locale, env, opts)
    {scope, subject} = Map.fetch!(@surfaces, surface)
    translate = &text!(locale, scope <> "." <> &1, %{})

    html =
      Map.merge(assigns, %{t: &(translate.(&1) |> ExploreFeatures.h()), h: &ExploreFeatures.h/1})

    message = %{
      from: env["SMTP_FROM"],
      to: recipient.email,
      locale: locale,
      subject: text!(locale, subject, %{"requester" => assigns[:requester]}),
      html: Layout.html(locale, body(surface, :html, html))
    }

    if surface == :test_email do
      Map.put(message, :format, :html_only)
    else
      Map.put(message, :text, Layout.text(body(surface, :text, Map.put(assigns, :t, translate))))
    end
  end

  defp assigns(:otp_account_locked, recipient, _locale, _env, opts),
    do: %{
      email: recipient.email,
      reset_url: Keyword.fetch!(opts, :base_url) <> "/users/password/new"
    }

  defp assigns(:location_request, _recipient, _locale, _env, opts) do
    %{
      requester: Keyword.fetch!(opts, :requester),
      request_url:
        Keyword.fetch!(opts, :base_url) <>
          "/family/location_requests/" <> to_string(Keyword.fetch!(opts, :request_id))
    }
  end

  defp assigns(:test_email, _recipient, locale, _env, opts),
    do: %{sent_at: sent_at(Keyword.fetch!(opts, :clock), locale)}

  defp sent_at(%{valid: true, local: local}, locale), do: LocalizedTime.l(locale, local, "long")

  defp sent_at(%{local: local, offset: offset, zone: zone}, _locale),
    do: Calendar.strftime(local, "%Y-%m-%d %H:%M:%S") <> " " <> LocalTime.offset(zone, offset)

  defp text!(locale, key, bindings) do
    case I18n.t(locale, key, bindings) do
      {:ok, text} when is_binary(text) -> text
      _ -> raise "missing residual mail translation"
    end
  end
end
