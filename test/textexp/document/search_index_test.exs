defmodule Textexp.Document.SearchIndexTest do
  use Textexp.DataCase

  alias Textexp.Document.SearchIndex
  alias Textexp.Fixtures

  setup do
    user = Fixtures.confirmed_user()
    %{user: user, document: Fixtures.create_document!(user, %{title: "Recette de la tarte"})}
  end

  test "searches the documents of its user", %{user: user, document: document} do
    {:ok, index} = SearchIndex.start_link(user)

    assert {:ok, [%{id: id}]} = SearchIndex.search(index, "tarte")
    assert id == document.id
    assert {:ok, []} = SearchIndex.search(index, "gâteau")
  end

  test "finds the other forms of a word, whatever its accents", %{user: user} do
    statuts = Fixtures.create_document!(user, %{title: "Les statuts de l'association"})
    ecole = Fixtures.create_document!(user, %{title: "Rentrée à l'École"})
    {:ok, index} = SearchIndex.start_link(user)

    assert {:ok, [%{id: id}]} = SearchIndex.search(index, "statut")
    assert id == statuts.id
    assert {:ok, [%{id: id}]} = SearchIndex.search(index, "ecoles")
    assert id == ecole.id
  end

  test "takes apostrophes as word separators, not quotes", %{user: user} do
    statuts = Fixtures.create_document!(user, %{title: "Les statuts de l'association"})
    {:ok, index} = SearchIndex.start_link(user)

    assert {:ok, [%{id: id}]} = SearchIndex.search(index, "l'association")
    assert id == statuts.id
  end

  test "finds the words its last word starts", %{user: user} do
    association = Fixtures.create_document!(user, %{title: "Les statuts de l'association"})
    {:ok, index} = SearchIndex.start_link(user)

    assert {:ok, [%{id: id}]} = SearchIndex.search(index, "associa")
    assert id == association.id
    assert {:ok, [%{id: ^id}]} = SearchIndex.search(index, "l'Associ")
    # only the last word
    assert {:ok, []} = SearchIndex.search(index, "assoc tartelette")
    # a single letter would find too many words
    assert {:ok, []} = SearchIndex.search(index, "z")
  end

  test "stop/1 ends it at once, without ending its caller", %{user: user} do
    {:ok, index} = SearchIndex.start_link(user)
    ref = Process.monitor(index)

    assert :ok = SearchIndex.stop(index)

    assert_receive {:DOWN, ^ref, :process, ^index, :shutdown}
    assert Process.alive?(self())
  end

  test "ends with the process that started it", %{user: user} do
    test = self()

    owner =
      spawn(fn ->
        {:ok, index} = SearchIndex.start_link(user)
        send(test, {:index, index})
        receive do: (:stop -> exit(:shutdown))
      end)

    assert_receive {:index, index}
    ref = Process.monitor(index)
    send(owner, :stop)

    assert_receive {:DOWN, ^ref, :process, ^index, :shutdown}
  end
end
