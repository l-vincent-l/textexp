defmodule Textexp.Document.Markdown do
  @moduledoc """
  Calculation of a document's content as Markdown, from its saved snapshot:
  while the document is being edited, it can miss the changes of the last
  seconds (see `Textexp.Document.YPersistence`).
  """
  use Ash.Resource.Calculation

  alias Textexp.Document.Body

  @impl true
  def load(_query, _opts, _context), do: [:snapshot]

  @impl true
  def calculate(documents, _opts, _context) do
    Enum.map(documents, &markdown(&1.snapshot))
  end

  defp markdown(nil), do: ""

  defp markdown(snapshot) do
    doc = Yex.Doc.new()
    Yex.apply_update(doc, snapshot)
    Body.to_markdown(doc)
  end
end
