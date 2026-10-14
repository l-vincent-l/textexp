// BlockNote editor of a document, synced with the server through Yjs. Loaded on
// demand by the DocumentEditor hook (document_editor.js); its CSS is the
// separate blocknote.css bundle, linked by the document page.
import * as React from "react";
import { useCreateBlockNote } from "@blocknote/react";
import { BlockNoteView } from "@blocknote/mantine";
import * as Y from "yjs";

import { withCollaboration } from "@blocknote/core/yjs";

import { createRoot } from "react-dom/client";
import { PhoenixChannelProvider } from "y-phoenix-channel";
import { IndexeddbPersistence } from "y-indexeddb";
import { Socket } from "phoenix";

const usercolors = [
  "#30bced",
  "#6eeb83",
  "#ffbc42",
  "#ecd444",
  "#ee6352",
  "#9ac2c9",
  "#8acb88",
  "#1be7ff",
];

const myColor = usercolors[Math.floor(Math.random() * usercolors.length)];

// One socket for the whole page, shared by the editors of the documents opened
// one after the other.
let socket: Socket | null = null;

function getSocket(): Socket {
  if (!socket) {
    // The CSRF token lets Phoenix pass the session (and thus the user) to the socket.
    const csrfToken = document
      .querySelector("meta[name='csrf-token']")
      ?.getAttribute("content");
    socket = new Socket("/socket", { params: { _csrf_token: csrfToken } });
    socket.connect();
  }
  return socket;
}

type EditorProps = {
  provider: PhoenixChannelProvider;
  fragment: Y.XmlFragment;
  userName: string;
};

function Editor({ provider, fragment, userName }: EditorProps) {
  const editor = useCreateBlockNote(
    withCollaboration({
      collaboration: {
        provider,
        fragment,
        user: { name: userName, color: myColor },
      },
    }),
  );

  return <BlockNoteView editor={editor} theme="light" />;
}

/**
 * Mounts the editor of the document described by `el` (`data-document-id`,
 * `data-user-name`), which holds the loading skeleton and the hidden editor
 * node. Returns the function that tears it all down.
 */
export function mountEditor(el: HTMLElement): () => void {
  const documentId = el.dataset.documentId;
  if (!documentId) {
    throw new Error("data-document-id missing on the editor element");
  }

  const editorNode = el.querySelector<HTMLElement>("[data-editor]");
  if (!editorNode) {
    throw new Error("editor node not found");
  }

  const ydoc = new Y.Doc();
  const provider = new PhoenixChannelProvider(
    getSocket(),
    `y_doc_room:${documentId}`,
    ydoc,
  );
  const persistence = new IndexeddbPersistence(`document:${documentId}`, ydoc);
  const fragment = ydoc.getXmlFragment("document-store");

  // Replaces the loading skeleton with the editor once the content is there:
  // synced with the server, or loaded from IndexedDB when this browser already
  // has a copy (e.g. offline).
  const showEditor = () => {
    el.querySelector("[data-skeleton]")?.remove();
    editorNode.hidden = false;
  };

  provider.on("sync", (synced: boolean) => {
    if (synced) showEditor();
  });
  persistence.whenSynced.then(() => {
    if (fragment.length > 0) showEditor();
  });

  const root = createRoot(editorNode);
  root.render(
    <Editor
      provider={provider}
      fragment={fragment}
      userName={el.dataset.userName ?? ""}
    />,
  );

  return () => {
    root.unmount();
    // leaves the document's channel, which stops tracking us as a viewer
    provider.destroy();
    persistence.destroy();
    ydoc.destroy();
  };
}
