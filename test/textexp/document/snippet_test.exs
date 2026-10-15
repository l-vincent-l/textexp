defmodule Textexp.Document.SnippetTest do
  use ExUnit.Case, async: true

  alias Textexp.Document.Snippet

  describe "terms/1" do
    test "keeps the searched words, lowercased" do
      assert Snippet.terms("Chat chien") == MapSet.new(["chat", "chien"])
    end

    test "drops field prefixes, operators, boosts and excluded words" do
      assert Snippet.terms(~s(title:chat AND "le chien" -oiseau NOT poisson été^2 OR loup)) ==
               MapSet.new(["chat", "le", "chien", "été", "loup"])
    end
  end

  describe "fragment/3" do
    test "is nil when the text has none of the words" do
      assert Snippet.fragment("rien ici", Snippet.terms("chat")) == nil
    end

    test "marks whole words only, whatever their case" do
      assert Snippet.fragment("Chats et Chat", Snippet.terms("chat")) ==
               [text: "Chats et ", match: "Chat"]
    end

    test "cuts a long text around the words, on word boundaries" do
      text =
        String.duplicate("Lorem ipsum dolor sit amet. ", 10) <>
          "Le chat dort.\nPuis le chien arrive. " <> String.duplicate("Fin du texte. ", 10)

      assert [
               {:text, "…" <> _},
               {:match, "chat"},
               {:text, middle},
               {:match, "chien"},
               {:text, last}
             ] =
               Snippet.fragment(text, Snippet.terms("chat chien"), 80)

      # line breaks become spaces
      assert middle == " dort. Puis le "
      assert String.ends_with?(last, "…")
      refute String.ends_with?(last, " …")
    end

    test "prefers the part holding the most different words" do
      text = "chat " <> String.duplicate("bla ", 50) <> "chat et chien"

      assert [{:text, "…bla bla "}, {:match, "chat"}, {:text, " et "}, {:match, "chien"}] =
               Snippet.fragment(text, Snippet.terms("chat chien"), 40)
    end
  end
end
