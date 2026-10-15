defmodule Textexp.Document.BodyTest do
  use ExUnit.Case, async: true

  alias Textexp.Document.Body

  # Body as written by the BlockNote editor: one block per
  # `{tag, text, nested blocks, attributes}`, the last two being optional.
  defp doc_with(blocks) do
    doc = Yex.Doc.new()
    fragment = Yex.Doc.get_xml_fragment(doc, "document-store")
    Yex.XmlFragment.push(fragment, Yex.XmlElementPrelim.empty("blockGroup"))
    {:ok, group} = Yex.XmlFragment.fetch(fragment, 0)
    push_blocks(group, blocks)

    doc
  end

  # Attributes are set once the elements exist: Yex ignores those of prelims.
  defp push_blocks(group, blocks) do
    for block <- blocks do
      {tag, text, children, attributes} =
        case block do
          {tag, text} -> {tag, text, [], %{}}
          {tag, text, children} -> {tag, text, children, %{}}
          block -> block
        end

      Yex.XmlElement.push(group, Yex.XmlElementPrelim.empty("blockContainer"))
      {:ok, container} = Yex.XmlElement.fetch(group, Yex.XmlElement.length(group) - 1)

      content = if text == "", do: [], else: [Yex.XmlTextPrelim.from(text)]
      Yex.XmlElement.push(container, Yex.XmlElementPrelim.new(tag, content))
      {:ok, element} = Yex.XmlElement.fetch(container, 0)
      for {key, value} <- attributes, do: Yex.XmlElement.insert_attribute(element, key, value)

      if children != [] do
        Yex.XmlElement.push(container, Yex.XmlElementPrelim.empty("blockGroup"))
        {:ok, nested} = Yex.XmlElement.fetch(container, 1)
        push_blocks(nested, children)
      end
    end
  end

  describe "excerpt/1" do
    test "is nil for an empty body" do
      assert Body.excerpt(Yex.Doc.new()) == nil
      assert Body.excerpt(doc_with([{"paragraph", ""}])) == nil
    end

    test "has the first three non-blank blocks, one per line, nested ones included" do
      doc =
        doc_with([
          {"heading", "Title"},
          {"paragraph", "  "},
          {"bulletListItem", "Item", [{"bulletListItem", "Sub item"}]},
          {"paragraph", "Not shown"}
        ])

      assert Body.excerpt(doc) == "Title\nItem\nSub item"
    end

    test "keeps the text of formatted parts" do
      doc = Yex.Doc.new()

      text =
        Yex.XmlTextPrelim.from([
          %{insert: "Hello "},
          %{insert: "world", attributes: %{"bold" => true}}
        ])

      doc
      |> Yex.Doc.get_xml_fragment("document-store")
      |> Yex.XmlFragment.push(
        Yex.XmlElementPrelim.new("blockGroup", [
          Yex.XmlElementPrelim.new("blockContainer", [
            Yex.XmlElementPrelim.new("paragraph", [text])
          ])
        ])
      )

      assert Body.excerpt(doc) == "Hello world"
    end

    test "is cut to 280 characters" do
      excerpt = Body.excerpt(doc_with([{"paragraph", String.duplicate("a", 400)}]))

      assert String.length(excerpt) == 280
    end
  end

  describe "to_markdown/1" do
    test "is empty for an empty body" do
      assert Body.to_markdown(Yex.Doc.new()) == ""
      assert Body.to_markdown(doc_with([{"paragraph", ""}])) == ""
    end

    test "separates blocks with a blank line and skips empty paragraphs" do
      doc =
        doc_with([
          {"heading", "Title", [], %{"level" => "2"}},
          {"paragraph", "First"},
          {"paragraph", ""},
          {"quote", "Quoted"},
          {"codeBlock", "x = 1", [], %{"language" => "elixir"}}
        ])

      assert Body.to_markdown(doc) ==
               "## Title\n\nFirst\n\n> Quoted\n\n```elixir\nx = 1\n```"
    end

    test "keeps list items together and nests children under their item" do
      doc =
        doc_with([
          {"numberedListItem", "One", [{"bulletListItem", "Sub"}]},
          {"numberedListItem", "Two"},
          {"checkListItem", "Done", [], %{"checked" => "true"}},
          {"checkListItem", "Todo", [], %{"checked" => "false"}},
          {"paragraph", "After"},
          {"numberedListItem", "Again"}
        ])

      assert Body.to_markdown(doc) ==
               "1. One\n   - Sub\n2. Two\n- [x] Done\n- [ ] Todo\n\nAfter\n\n1. Again"
    end

    test "writes the formatting of the text" do
      doc = Yex.Doc.new()

      text =
        Yex.XmlTextPrelim.from([
          %{insert: "Plain "},
          %{insert: "bold ", attributes: %{"bold" => %{}}},
          %{insert: "both", attributes: %{"bold" => %{}, "italic" => %{}}},
          %{insert: " and "},
          %{insert: "a link", attributes: %{"link" => %{"href" => "https://example.com"}}}
        ])

      doc
      |> Yex.Doc.get_xml_fragment("document-store")
      |> Yex.XmlFragment.push(
        Yex.XmlElementPrelim.new("blockGroup", [
          Yex.XmlElementPrelim.new("blockContainer", [
            Yex.XmlElementPrelim.new("paragraph", [text])
          ])
        ])
      )

      assert Body.to_markdown(doc) ==
               "Plain **bold** _**both**_ and [a link](https://example.com)"
    end

    test "writes images with their caption" do
      doc =
        doc_with([
          {"image", "", [], %{"url" => "https://example.com/a.png", "caption" => "A cat"}}
        ])

      assert Body.to_markdown(doc) == "![A cat](https://example.com/a.png)"
    end
  end

  describe "empty?/1" do
    test "is true without text and with only paragraphs" do
      assert Body.empty?(Yex.Doc.new())
      assert Body.empty?(doc_with([{"paragraph", ""}, {"paragraph", " "}]))
    end

    test "is false with text or another block" do
      refute Body.empty?(doc_with([{"paragraph", "hello"}]))
      refute Body.empty?(doc_with([{"image", ""}]))
    end
  end
end
