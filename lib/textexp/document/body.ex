defmodule Textexp.Document.Body do
  @moduledoc """
  The body of a document: the XmlFragment written by the BlockNote editor
  (blocknote.tsx), made of nested `blockGroup` > `blockContainer` > block
  elements (`paragraph`, `heading`...).
  """

  @fragment "document-store"
  # Tags of an empty BlockNote body: the block structure and empty paragraphs
  @empty_tags ["blockGroup", "blockContainer", "paragraph"]
  @excerpt_lines 3
  @excerpt_length 280

  @doc """
  The body is empty when it has no text and only holds empty paragraphs: any
  other block (image, table, divider...) counts as content.
  """
  def empty?(doc) do
    xml = doc |> fragment() |> Yex.XmlFragment.to_string()
    tags = Regex.scan(~r/<([A-Za-z][\w-]*)/, xml, capture: :all_but_first) |> List.flatten()
    text = Regex.replace(~r/<[^>]*>/, xml, "")

    String.trim(text) == "" and Enum.all?(tags, &(&1 in @empty_tags))
  end

  @doc """
  The first non-blank lines of the body, one per block, joined with newlines,
  to preview the document. `nil` when the body has no text.
  """
  def excerpt(doc) do
    doc
    |> fragment()
    |> Yex.XmlFragment.children()
    |> Stream.flat_map(&lines/1)
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Enum.take(@excerpt_lines)
    |> Enum.join("\n")
    |> String.slice(0, @excerpt_length)
    |> case do
      "" -> nil
      excerpt -> excerpt
    end
  end

  defp fragment(doc), do: Yex.Doc.get_xml_fragment(doc, @fragment)

  # One line per element holding text, in document order.
  defp lines(%Yex.XmlElement{} = element) do
    children = element |> Yex.XmlElement.children() |> Enum.to_list()
    texts = for %Yex.XmlText{} = text <- children, do: text(text)
    own = if texts == [], do: [], else: [Enum.join(texts)]

    own ++ Enum.flat_map(children, &lines/1)
  end

  defp lines(_text), do: []

  # Plain text, without formatting or embeds (mentions, images...).
  defp text(xml_text) do
    for %{insert: insert} when is_binary(insert) <- Yex.XmlText.to_delta(xml_text),
        into: "",
        do: insert
  end
end
