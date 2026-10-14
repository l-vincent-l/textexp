defmodule Textexp.Document.BodyTest do
  use ExUnit.Case, async: true

  alias Textexp.Document.Body

  # Body as written by the BlockNote editor: one block per `{tag, children}`
  # pair, where children are strings (text) or nested blocks.
  defp doc_with(blocks) do
    doc = Yex.Doc.new()

    doc
    |> Yex.Doc.get_xml_fragment("document-store")
    |> Yex.XmlFragment.push(block_group(blocks))

    doc
  end

  defp block_group(blocks) do
    Yex.XmlElementPrelim.new("blockGroup", Enum.map(blocks, &block_container/1))
  end

  defp block_container({tag, text}) when is_binary(text), do: block_container({tag, text, []})

  defp block_container({tag, text, children}) do
    content = if text == "", do: [], else: [Yex.XmlTextPrelim.from(text)]
    nested = if children == [], do: [], else: [block_group(children)]
    Yex.XmlElementPrelim.new("blockContainer", [Yex.XmlElementPrelim.new(tag, content) | nested])
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
