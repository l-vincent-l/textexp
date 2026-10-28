defmodule YBlocknoteTest do
  use ExUnit.Case, async: true

  # Document as written by the BlockNote editor: one block per
  # `{tag, text, nested blocks, attributes}`, the last two being optional.
  defp fragment_with(blocks) do
    fragment = new_fragment()
    Yex.XmlFragment.push(fragment, Yex.XmlElementPrelim.empty("blockGroup"))
    {:ok, group} = Yex.XmlFragment.fetch(fragment, 0)
    push_blocks(group, blocks)

    fragment
  end

  defp new_fragment, do: Yex.Doc.get_xml_fragment(Yex.Doc.new(), "blocknote")

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

  describe "to_text/1" do
    test "has one line per block holding text, nested ones included" do
      fragment =
        fragment_with([
          {"heading", "Title", [], %{"level" => "1"}},
          {"paragraph", ""},
          {"bulletListItem", "Item", [{"bulletListItem", "Sub item"}]}
        ])

      assert YBlocknote.to_text(fragment) == "Title\nItem\nSub item"
    end
  end

  describe "to_markdown/1" do
    test "is empty for an empty body" do
      assert YBlocknote.to_markdown(new_fragment()) == ""
      assert YBlocknote.to_markdown(fragment_with([{"paragraph", ""}])) == ""
    end

    # BlockNote stores the level as a number, which y_ex reads as a float.
    test "reads the heading level as a number or as text" do
      fragment =
        fragment_with([
          {"heading", "One", [], %{"level" => 1}},
          {"heading", "Two", [], %{"level" => 2.0}},
          {"heading", "Three", [], %{"level" => "3"}}
        ])

      assert YBlocknote.to_markdown(fragment) == "# One\n\n## Two\n\n### Three"
    end

    test "separates blocks with a blank line and skips empty paragraphs" do
      fragment =
        fragment_with([
          {"heading", "Title", [], %{"level" => "2"}},
          {"paragraph", "First"},
          {"paragraph", ""},
          {"quote", "Quoted"},
          {"codeBlock", "x = 1", [], %{"language" => "elixir"}}
        ])

      assert YBlocknote.to_markdown(fragment) ==
               "## Title\n\nFirst\n\n> Quoted\n\n```elixir\nx = 1\n```"
    end

    test "keeps list items together and nests children under their item" do
      fragment =
        fragment_with([
          {"numberedListItem", "One", [{"bulletListItem", "Sub"}]},
          {"numberedListItem", "Two"},
          {"checkListItem", "Done", [], %{"checked" => "true"}},
          {"checkListItem", "Todo", [], %{"checked" => "false"}},
          {"paragraph", "After"},
          {"numberedListItem", "Again"}
        ])

      assert YBlocknote.to_markdown(fragment) ==
               "1. One\n   - Sub\n2. Two\n- [x] Done\n- [ ] Todo\n\nAfter\n\n1. Again"
    end

    test "writes the formatting of the text" do
      fragment = new_fragment()

      text =
        Yex.XmlTextPrelim.from([
          %{insert: "Plain "},
          %{insert: "bold ", attributes: %{"bold" => %{}}},
          %{insert: "both", attributes: %{"bold" => %{}, "italic" => %{}}},
          %{insert: " and "},
          %{insert: "a link", attributes: %{"link" => %{"href" => "https://example.com"}}}
        ])

      Yex.XmlFragment.push(
        fragment,
        Yex.XmlElementPrelim.new("blockGroup", [
          Yex.XmlElementPrelim.new("blockContainer", [
            Yex.XmlElementPrelim.new("paragraph", [text])
          ])
        ])
      )

      assert YBlocknote.to_markdown(fragment) ==
               "Plain **bold** _**both**_ and [a link](https://example.com)"
    end

    test "writes images with their caption" do
      fragment =
        fragment_with([
          {"image", "", [], %{"url" => "https://example.com/a.png", "caption" => "A cat"}}
        ])

      assert YBlocknote.to_markdown(fragment) == "![A cat](https://example.com/a.png)"
    end
  end

  describe "empty?/1" do
    test "is true without text and with only paragraphs" do
      assert YBlocknote.empty?(new_fragment())
      assert YBlocknote.empty?(fragment_with([{"paragraph", ""}, {"paragraph", " "}]))
    end

    test "is false with text or another block" do
      refute YBlocknote.empty?(fragment_with([{"paragraph", "hello"}]))
      refute YBlocknote.empty?(fragment_with([{"image", ""}]))
    end
  end
end
