defmodule DawarichWeb.TripRichText do
  @moduledoc false
  use DawarichWeb, :html

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :value, :string, default: nil
  attr :revision, :integer, default: 1
  attr :label, :string, required: true
  attr :locale, :string, required: true

  def editor(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="RichText"
      phx-update="ignore"
      data-revision={@revision}
      data-upload-failed={t(@locale, "javascript.upload.none_uploaded", %{})}
      class="trip-rich-text [&_trix-toolbar_.trix-button-group--file-tools]:inline-flex"
    >
      <input type="hidden" id={"#{@id}-input"} name={@name} value={@value} />
      <trix-editor
        input={"#{@id}-input"}
        class="trix-content textarea textarea-bordered w-full min-h-48"
        role="textbox"
        aria-multiline="true"
        aria-label={@label}
      >
      </trix-editor>
      <p data-rich-status class="text-sm text-error mt-1" role="status" aria-live="polite"></p>
    </div>
    """
  end
end
