// blocknote.tsx を blocknote ディレクトリに移動
import * as React from "react";
import "@blocknote/core/fonts/inter.css";
import { useCreateBlockNote } from "@blocknote/react";
import { BlockNoteView } from "@blocknote/mantine";
import * as Y from "yjs";
import "@blocknote/mantine/style.css";

import { withCollaboration } from "@blocknote/core/yjs";

import { createRoot } from "react-dom/client";
import { PhoenixChannelProvider } from "y-phoenix-channel";
import { IndexeddbPersistence } from "y-indexeddb";
import { Socket } from "phoenix";

const domNode = document.getElementById("root");
if (!domNode) {
  throw new Error("root element not found");
}

// The CSRF token lets Phoenix pass the session (and thus the user) to the socket.
const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  ?.getAttribute("content");
const socket = new Socket("/socket", { params: { _csrf_token: csrfToken } });
socket.connect();
const ydoc = new Y.Doc();
const documentId = domNode.dataset.documentId;
if (!documentId) {
  throw new Error("data-document-id missing on root element");
}

const provider = new PhoenixChannelProvider(
  socket,
  `y_doc_room:${documentId}`,
  ydoc,
);
const persistence = new IndexeddbPersistence(`document:${documentId}`, ydoc);

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
export default function App() {
  // Creates a new editor instance.
  const editor = useCreateBlockNote(
    withCollaboration({
    collaboration: {
      provider,
      fragment: ydoc.getXmlFragment("document-store"),
      user: {
        name: domNode.dataset.userName ?? "",
        color: myColor,
      },
    },
    // ...
    })
    );

  // Renders the editor instance using a React component.
  return <BlockNoteView editor={editor} theme="light" />;
}

const root = createRoot(domNode);
root.render(<App />);
