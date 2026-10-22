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
    |> text_lines()
    |> Enum.take(@excerpt_lines)
    |> Enum.join("\n")
    |> String.slice(0, @excerpt_length)
    |> case do
      "" -> nil
      excerpt -> excerpt
    end
  end

  @doc """
  The text of the body, without formatting: one line per block holding text.
  """
  def text(doc), do: doc |> text_lines() |> Enum.join("\n")

  defp text_lines(doc) do
    doc
    |> fragment()
    |> Yex.XmlFragment.children()
    |> Stream.flat_map(&lines/1)
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
  end

  @doc """
  The body as Markdown, one block after the other, nested blocks indented under
  their parent. Text colors, alignment and underline have no Markdown
  equivalent and are dropped; so are blocks without text, such as empty
  paragraphs.
  """
  def to_markdown(doc) do
    doc
    |> fragment()
    |> Yex.XmlFragment.children()
    |> Enum.flat_map(&blocks/1)
    |> join_blocks()
  end

  defp fragment(doc), do: Yex.Doc.get_xml_fragment(doc, @fragment)

  # The blocks of a blockGroup, as `{kind, markdown}` where kind tells whether
  # consecutive blocks belong to the same list.
  defp blocks(%Yex.XmlElement{} = group) do
    {blocks, _number} =
      group
      |> Yex.XmlElement.children()
      |> Enum.flat_map_reduce(0, &block_container/2)

    blocks
  end

  defp blocks(_text), do: []

  # A blockContainer holds its block, then the blockGroup of its nested blocks
  # if it has some. `number` is the number of the previous item of a numbered
  # list, 0 if the previous block is not one.
  defp block_container(container, number) do
    [block | nested] = container |> Yex.XmlElement.children() |> Enum.to_list()
    tag = Yex.XmlElement.get_tag(block)
    number = if tag == "numberedListItem", do: number + 1, else: 0

    case block(tag, block, number) do
      nil ->
        {Enum.flat_map(nested, &blocks/1), number}

      {kind, markdown} ->
        children = nested |> Enum.flat_map(&blocks/1) |> join_blocks()
        {[{kind, nest(markdown, children, kind)}], number}
    end
  end

  defp block("heading", block, _number) do
    level = block |> Yex.XmlElement.get_attribute("level") |> to_string()
    text_block(:block, String.duplicate("#", String.to_integer(level)) <> " ", block)
  end

  defp block("bulletListItem", block, _number), do: text_block(:list, "- ", block)
  defp block("toggleListItem", block, _number), do: text_block(:list, "- ", block)
  defp block("numberedListItem", block, number), do: text_block(:list, "#{number}. ", block)

  defp block("checkListItem", block, _number) do
    checked = to_string(Yex.XmlElement.get_attribute(block, "checked")) == "true"
    text_block(:list, if(checked, do: "- [x] ", else: "- [ ] "), block)
  end

  defp block("quote", block, _number) do
    case inline(block) do
      "" -> nil
      text -> {:block, text |> String.split("\n") |> Enum.map_join("\n", &("> " <> &1))}
    end
  end

  defp block("codeBlock", block, _number) do
    language = Yex.XmlElement.get_attribute(block, "language") || ""
    {:block, "```#{language}\n#{plain_text(block)}\n```"}
  end

  defp block("table", block, _number), do: {:block, table(block)}
  defp block("divider", _block, _number), do: {:block, "---"}

  defp block(tag, block, _number) when tag in ["image", "video", "audio", "file"] do
    url = Yex.XmlElement.get_attribute(block, "url")

    name =
      Yex.XmlElement.get_attribute(block, "caption") ||
        Yex.XmlElement.get_attribute(block, "name")

    name = if name in [nil, ""], do: url, else: name

    cond do
      url in [nil, ""] -> nil
      tag == "image" -> {:block, "![#{name}](#{url})"}
      true -> {:block, "[#{name}](#{url})"}
    end
  end

  # Paragraphs, and blocks unknown to this module, keep their text.
  defp block(_tag, block, _number), do: text_block(:block, "", block)

  defp text_block(kind, prefix, block) do
    case inline(block) do
      "" -> nil
      text -> {kind, prefix <> text}
    end
  end

  # Nested blocks go under their parent, indented to the parent's text so that
  # they stay in the same list item.
  defp nest(markdown, "", _kind), do: markdown

  defp nest(markdown, children, kind) do
    indent = if kind == :list, do: list_marker_width(markdown), else: 2
    separator = if kind == :list, do: "\n", else: "\n\n"
    markdown <> separator <> indent(children, String.duplicate(" ", indent))
  end

  defp list_marker_width(markdown) do
    [marker] = Regex.run(~r/^(?:- \[[ x]\] |- |\d+\. )/, markdown)
    String.length(marker)
  end

  defp indent(markdown, indent) do
    markdown
    |> String.split("\n")
    |> Enum.map_join("\n", fn
      "" -> ""
      line -> indent <> line
    end)
  end

  # Items of the same list are on consecutive lines; other blocks are
  # separated by a blank line.
  defp join_blocks([]), do: ""

  defp join_blocks([{_kind, first} | _] = blocks) do
    blocks
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map_join(fn [{previous, _}, {kind, markdown}] ->
      if previous == :list and kind == :list, do: "\n" <> markdown, else: "\n\n" <> markdown
    end)
    |> then(&(first <> &1))
  end

  # The rows of a table, the first one taken as header; each cell holds its
  # text in a tableParagraph.
  defp table(table) do
    rows =
      for row <- Yex.XmlElement.children(table) do
        for cell <- Yex.XmlElement.children(row) do
          cell
          |> Yex.XmlElement.children()
          |> Enum.map_join(" ", &inline/1)
          |> String.replace("|", "\\|")
          |> String.replace("\n", " ")
        end
      end

    case rows do
      [] ->
        ""

      [header | body] ->
        separator = Enum.map(header, fn _ -> "---" end)
        Enum.map_join([header, separator | body], "\n", &("| " <> Enum.join(&1, " | ") <> " |"))
    end
  end

  # Text of an element with its formatting as Markdown.
  defp inline(%Yex.XmlElement{} = element) do
    element
    |> Yex.XmlElement.children()
    |> Enum.map_join(&inline/1)
    |> String.trim()
  end

  defp inline(%Yex.XmlText{} = text) do
    for %{insert: insert} = part when is_binary(insert) <- Yex.XmlText.to_delta(text),
        into: "",
        do: format(insert, Map.get(part, :attributes, %{}))
  end

  defp plain_text(element) do
    for %Yex.XmlText{} = text <- Yex.XmlElement.children(element), into: "", do: xml_text(text)
  end

  # Marks are applied inside out; the spaces around a formatted part are kept
  # outside of its markers, which Markdown would not recognize otherwise.
  defp format(text, attributes) do
    case Regex.run(~r/^(\s*)(.*?)(\s*)$/s, text) do
      [_, leading, "", trailing] ->
        leading <> trailing

      [_, leading, core, trailing] ->
        core =
          [
            {"code", &"`#{&1}`"},
            {"bold", &"**#{&1}**"},
            {"italic", &"_#{&1}_"},
            {"strike", &"~~#{&1}~~"}
          ]
          |> Enum.reduce(core, fn {mark, wrap}, core ->
            if mark?(attributes, mark), do: wrap.(core), else: core
          end)
          |> link(attributes["link"])

        leading <> core <> trailing
    end
  end

  defp mark?(attributes, mark), do: attributes[mark] not in [nil, false]

  defp link(text, %{"href" => href}) when is_binary(href), do: "[#{text}](#{href})"
  defp link(text, _), do: text

  # One line per element holding text, in document order.
  defp lines(%Yex.XmlElement{} = element) do
    children = element |> Yex.XmlElement.children() |> Enum.to_list()
    texts = for %Yex.XmlText{} = text <- children, do: xml_text(text)
    own = if texts == [], do: [], else: [Enum.join(texts)]

    own ++ Enum.flat_map(children, &lines/1)
  end

  defp lines(_text), do: []

  # Plain text, without formatting or embeds (mentions, images...).
  defp xml_text(xml_text) do
    for %{insert: insert} when is_binary(insert) <- Yex.XmlText.to_delta(xml_text),
        into: "",
        do: insert
  end
end
