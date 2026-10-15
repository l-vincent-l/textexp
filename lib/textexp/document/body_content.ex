defmodule Textexp.Document.BodyContent do
  @moduledoc """
  Calculation of a document's body, from its saved snapshot, as Markdown
  (`format: :markdown`) or plain text (`format: :text`, see
  `Textexp.Document.Body`). While the document is being edited, it can miss the
  changes of the last seconds (see `Textexp.Document.YPersistence`).
  """
  use Ash.Resource.Calculation

  alias Textexp.Document.Body

  @impl true
  def init(opts) do
    if opts[:format] in [:markdown, :text],
      do: {:ok, opts},
      else: {:error, "format must be :markdown or :text"}
  end

  @impl true
  def load(_query, _opts, _context), do: [:snapshot]

  @impl true
  def calculate(documents, opts, _context) do
    Enum.map(documents, &content(&1.snapshot, opts[:format]))
  end

  defp content(nil, _format), do: ""

  defp content(snapshot, format) do
    doc = Yex.Doc.new()
    Yex.apply_update(doc, snapshot)

    case format do
      :markdown -> Body.to_markdown(doc)
      :text -> Body.text(doc)
    end
  end
end
