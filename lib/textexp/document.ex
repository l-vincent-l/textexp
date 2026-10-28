defmodule Textexp.Document do
  @moduledoc """
  The documents and who may access them: their owner can do anything, editors
  (see `Textexp.Document.Membership`) read and write, viewers only read (see
  `Textexp.Document.Policy`).

  Functions taking a `user` only see and change what that user may: listings
  are filtered in their query, an action reads the user's role, then checks it
  with `Policy`. The others, without user, are for the server itself: e.g.
  YPersistence saves the documents being edited, whose DocServer checks the
  rights of the clients (see `Textexp.Document.Access`).

  A change of a member's role is broadcast on `members_topic/1`, a rename on
  `Textexp.Document.YPersistence.topic/1`.
  """
  import Ecto.Query

  alias Ecto.Changeset
  alias Textexp.Accounts
  alias Textexp.Accounts.User
  alias Textexp.Document.{Body, Document, Membership, Policy, YPersistence}
  alias Textexp.SqliteRepo, as: Repo

  # Largest Yjs state an import accepts.
  @max_import_bytes 5_000_000

  # Read without their snapshot, which only the editor loads.
  @fields [:id, :title, :excerpt, :owner_id, :inserted_at, :updated_at]

  ## Reading

  # The documents `user` can read, each with `user`'s membership if any.
  defp readable_by(user) do
    from d in Document,
      as: :document,
      left_join: m in Membership,
      as: :membership,
      on: m.document_id == d.id and m.user_id == ^user.id,
      where: d.owner_id == ^user.id or not is_nil(m.id)
  end

  @doc "The documents `user` can read, last updated first."
  def list_documents(user) do
    readable_by(user)
    |> order_by(desc: :updated_at)
    |> select([document: d], struct(d, @fields))
    |> Repo.all()
  end

  @doc "Among `ids`, the documents `user` can read."
  def list_documents(user, ids) do
    readable_by(user)
    |> where([document: d], d.id in ^ids)
    |> select([document: d], struct(d, @fields))
    |> Repo.all()
  end

  @doc "The documents `user` can read, with the text of their body: `{document, text}`."
  def list_documents_with_text(user) do
    readable_by(user)
    |> select([document: d], struct(d, [:snapshot | @fields]))
    |> Repo.all()
    |> Enum.map(&{%{&1 | snapshot: nil}, body(&1.snapshot, :text)})
  end

  @doc """
  The document of `id`, if `user` can read it, with their `role` on it:
  `{:ok, document}` or `{:error, :not_found}`.
  """
  def get_document(id, user) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         {document, role} <-
           readable_by(user)
           |> where([document: d], d.id == ^id)
           |> select([document: d, membership: m], {struct(d, @fields), m.role})
           |> Repo.one() do
      {:ok, %{document | role: role(document, user, role)}}
    else
      _ -> {:error, :not_found}
    end
  end

  defp role(%Document{owner_id: owner_id}, %{id: owner_id}, _membership_role), do: :owner
  defp role(_document, _user, membership_role), do: membership_role

  @doc """
  The rights on the document of `id`: `%{owner_id, members}`, `members` giving
  the role of each member's id. Without owner for an unknown document.
  """
  def access_rights(id) do
    rows =
      case Ecto.UUID.cast(id) do
        {:ok, id} ->
          Repo.all(
            from d in Document,
              left_join: m in Membership,
              on: m.document_id == d.id,
              where: d.id == ^id,
              select: {d.owner_id, m.user_id, m.role}
          )

        :error ->
          []
      end

    owner_id =
      case rows do
        [{owner_id, _user_id, _role} | _] -> owner_id
        [] -> nil
      end

    %{
      owner_id: owner_id,
      members: for({_, user_id, role} <- rows, user_id, into: %{}, do: {user_id, role})
    }
  end

  @doc """
  PubSub topic on which `{:member_changed, document_id, user_id, role}` is
  broadcast when a member is added (`role`), changed, or removed (`nil`).
  """
  def members_topic(document_id), do: "document_members:#{document_id}"

  defp broadcast_member_changed(document_id, user_id, role) do
    Phoenix.PubSub.broadcast(
      Textexp.PubSub,
      members_topic(document_id),
      {:member_changed, document_id, user_id, role}
    )
  end

  # Runs `fun` if `user` may do `action` on the document of `id`, in the same
  # transaction as the reading of their role.
  defp authorized(id, user, action, fun) do
    Repo.transact(fn ->
      case get_document(id, user) do
        {:ok, document} ->
          if Policy.can?(document.role, action), do: fun.(document), else: {:error, :forbidden}

        {:error, _} ->
          {:error, :forbidden}
      end
    end)
  end

  @doc """
  The document `user` opened last (see `opened/2`) if they can still read it,
  else the one last updated, else `nil`.
  """
  def last_opened(user) do
    readable_by(user)
    |> join(:inner, [], u in User, as: :user, on: u.id == ^user.id)
    |> order_by([document: d, user: u], desc: coalesce(d.id == u.last_document_id, false))
    |> order_by([document: d], desc: d.updated_at)
    |> limit(1)
    |> select([document: d], struct(d, @fields))
    |> Repo.one()
  end

  @doc "Remembers that `user` opened `document`, for `last_opened/1`."
  def opened(user, %Document{id: id}) do
    Repo.update_all(from(u in User, where: u.id == ^user.id), set: [last_document_id: id])
    :ok
  end

  @doc "The document of `id`, with its snapshot."
  def get_document!(id), do: Repo.get!(Document, id)

  @doc "The body of a document as Markdown, from its saved snapshot."
  def markdown(%Document{snapshot: snapshot}), do: body(snapshot, :markdown)

  # While the document is being edited, it can miss the changes of the last
  # seconds (see YPersistence).
  defp body(nil, _format), do: ""

  defp body(snapshot, format) do
    doc = Yex.Doc.new()
    Yex.apply_update(doc, snapshot)

    case format do
      :markdown -> Body.to_markdown(doc)
      :text -> Body.text(doc)
    end
  end

  ## Writing

  def create_document(user, attrs \\ %{}) do
    %Document{owner_id: user.id}
    |> Changeset.cast(attrs, [:title])
    |> Repo.insert()
  end

  @doc """
  Creates a document from the full Yjs state of its content, e.g. a file
  converted by BlockNote in the browser. The state is checked by applying it,
  and its excerpt saved along.
  """
  def import_document(user, title, snapshot) do
    doc = Yex.Doc.new()

    changeset =
      %Document{owner_id: user.id}
      |> Changeset.cast(%{title: title}, [:title])
      |> Changeset.put_change(:snapshot, snapshot)

    cond do
      not is_binary(snapshot) ->
        {:error, Changeset.add_error(changeset, :snapshot, "contenu illisible")}

      byte_size(snapshot) > @max_import_bytes ->
        {:error, Changeset.add_error(changeset, :snapshot, "contenu trop volumineux")}

      Yex.apply_update(doc, snapshot) == :ok ->
        changeset |> Changeset.put_change(:excerpt, Body.excerpt(doc)) |> Repo.insert()

      true ->
        {:error, Changeset.add_error(changeset, :snapshot, "contenu illisible")}
    end
  end

  @doc """
  Renames a document that `user` can write: owner or editor.
  `{:document_renamed, document_id, title, at}` is broadcast on
  `YPersistence.topic/1`, for the other pages showing it.
  """
  def rename_document(%Document{id: id}, user, title) do
    authorized(id, user, :write, fn document ->
      now = DateTime.utc_now()

      Repo.update_all(from(d in Document, where: d.id == ^id),
        set: [title: title, updated_at: now]
      )

      Phoenix.PubSub.broadcast(
        Textexp.PubSub,
        YPersistence.topic(id),
        {:document_renamed, id, title, now}
      )

      {:ok, %{document | title: title, updated_at: now}}
    end)
  end

  @doc """
  Replaces the snapshot of a document with the full Yjs state of its content,
  and its excerpt. A document saved without title, but with text, gets a
  dated one. Without text, it stays untitled so that it is deleted when left
  (see YPersistence.unbind).

  One `UPDATE … RETURNING`: the document saved, with its `title` and
  `updated_at`.
  """
  def save_snapshot(id, snapshot, excerpt) do
    dated_title = "Notes du #{Calendar.strftime(Date.utc_today(), "%d-%m-%Y")}"

    {1, [document]} =
      Repo.update_all(
        from(d in Document,
          where: d.id == ^id,
          update: [
            set: [
              snapshot: ^snapshot,
              excerpt: ^excerpt,
              updated_at: ^DateTime.utc_now(),
              # blank: NULL, or only spaces, tabs and line breaks
              title:
                fragment(
                  "CASE WHEN coalesce(trim(?, char(32, 9, 10, 13)), '') = '' AND ? IS NOT NULL THEN ? ELSE ? END",
                  d.title,
                  ^excerpt,
                  ^dated_title,
                  d.title
                )
            ]
          ],
          select: struct(d, [:id, :title, :updated_at])
        ),
        []
      )

    document
  end

  def delete_document(id) do
    Repo.delete_all(from d in Document, where: d.id == ^id)
    :ok
  end

  ## Members

  def change_share(attrs \\ %{}), do: Membership.share_changeset(%Membership{}, attrs)

  @doc """
  Shares a document that `owner` owns with the user of `attrs`' `email`, as
  `role`; changes the role of a member. Returns the member as listed by
  `list_members/2`.
  """
  def share_document(owner, document_id, attrs) do
    changeset = change_share(attrs)

    with {:ok, %{email: email, role: role}} <- Changeset.apply_action(changeset, :insert),
         {:ok, member} <-
           authorized(document_id, owner, :share, fn document ->
             with {:ok, user} <- member_user(changeset, email, owner) do
               %Membership{document_id: document.id, user_id: user.id, role: role}
               |> Repo.insert!(
                 on_conflict: [set: [role: role]],
                 conflict_target: [:document_id, :user_id]
               )

               {:ok, Enum.find(members(document.id), &(&1.user_id == user.id))}
             end
           end) do
      broadcast_member_changed(document_id, member.user_id, member.role)
      {:ok, member}
    end
  end

  defp member_user(changeset, email, owner) do
    case Accounts.get_user_by_email(email) do
      nil -> error(changeset, "aucun compte avec cette adresse")
      %{id: id} when id == owner.id -> error(changeset, "c'est l'adresse du propriétaire")
      # Whoever registered an unconfirmed account may not own its address.
      %{confirmed_at: nil} -> error(changeset, "ce compte n'a pas encore confirmé son adresse")
      user -> {:ok, user}
    end
  end

  defp error(changeset, message),
    do: {:error, %{Changeset.add_error(changeset, :email, message) | action: :insert}}

  @doc """
  The members of a document that `owner` owns: `%{id, user_id, email, role}`;
  none for another user.
  """
  def list_members(owner, document_id) do
    case authorized(document_id, owner, :share, &{:ok, members(&1.id)}) do
      {:ok, members} -> members
      {:error, _} -> []
    end
  end

  defp members(document_id) do
    Repo.all(
      from m in Membership,
        join: u in assoc(m, :user),
        where: m.document_id == ^document_id,
        order_by: u.email,
        select: %{id: m.id, user_id: u.id, email: u.email, role: m.role}
    )
  end

  @doc """
  Changes the role of a member of a document that `owner` owns: `role` is
  `"editor"` or `"viewer"`. Returns the member as listed by `list_members/2`.
  """
  def change_member_role(owner, membership_id, role) do
    with {:ok, membership_id} <- Ecto.UUID.cast(membership_id),
         {:ok, role} when not is_nil(role) <-
           Ecto.Type.cast(Membership.__schema__(:type, :role), role),
         %Membership{} = membership <- Repo.get(Membership, membership_id),
         {:ok, member} <-
           authorized(membership.document_id, owner, :share, fn document ->
             membership |> Changeset.change(role: role) |> Repo.update!()
             {:ok, Enum.find(members(document.id), &(&1.id == membership.id))}
           end) do
      broadcast_member_changed(membership.document_id, membership.user_id, role)
      {:ok, member}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Removes a member of a document that `owner` owns."
  def remove_member(owner, membership_id) do
    with {:ok, membership_id} <- Ecto.UUID.cast(membership_id),
         %Membership{} = membership <- Repo.get(Membership, membership_id),
         {:ok, _} <-
           authorized(membership.document_id, owner, :share, fn _document ->
             {:ok, Repo.delete!(membership)}
           end) do
      broadcast_member_changed(membership.document_id, membership.user_id, nil)
      :ok
    else
      _ -> {:error, :not_found}
    end
  end
end
