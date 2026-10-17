defmodule DawarichWeb.PlacesUI do
  @moduledoc false
  import Phoenix.Component
  import Phoenix.LiveView

  def message(locale),
    do: DawarichWeb.Translate.t(locale, "controllers.application.admin_action_failed", %{})

  def uncertain_message(locale) do
    messages = %{
      "en" => "The save outcome is unknown. Check your Places before saving again.",
      "de" => "Das Speicherergebnis ist unbekannt. Prüfe deine Orte, bevor du erneut speicherst.",
      "es" => "El resultado es desconocido. Revisa tus lugares antes de volver a guardar.",
      "fr" => "Le résultat est inconnu. Vérifiez vos lieux avant d’enregistrer à nouveau.",
      "pl" => "Wynik zapisu jest nieznany. Sprawdź miejsca przed ponownym zapisem.",
      "ru" => "Результат сохранения неизвестен. Проверьте места перед повторным сохранением.",
      "zh" => "保存结果未知。再次保存前，请检查你的地点。"
    }

    Map.get(messages, locale, messages["en"])
  end

  def refuse(socket, :stale_session) do
    socket
    |> assign(
      entries: [],
      form_state: nil,
      detail: nil,
      note_state: nil,
      place_data: nil,
      nearby_state: nil,
      confirmation: nil
    )
    |> redirect(to: "/users/sign_in")
  end

  def refuse(socket, _), do: assign(socket, :error, message(socket.assigns.locale))
end
