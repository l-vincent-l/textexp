// Hook of a document's editor element. The editor bundle (React, BlockNote,
// Yjs) is only loaded the first time a document is opened. The element's id
// changes with the document, so that LiveView replaces it when another
// document is opened: the old editor is destroyed and a new one mounted.
export const DocumentEditor = {
  mounted() {
    this.unmount = import("./blocknote/blocknote").then(({mountEditor}) =>
      this.isDestroyed ? null : mountEditor(this.el)
    )
  },

  destroyed() {
    this.isDestroyed = true
    this.unmount.then(unmount => unmount && unmount())
  },
}
