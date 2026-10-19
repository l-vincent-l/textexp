// Hook of a document's editor element. The editor bundle (React, BlockNote,
// Yjs) is only loaded the first time a document is opened. The element's id
// changes with the document, so that LiveView replaces it when another
// document is opened: the old editor is destroyed and a new one mounted.
export const DocumentEditor = {
  mounted() {
    const resolveUsers = ids =>
      new Promise(resolve =>
        this.pushEvent("resolve_users", {ids}, reply => resolve(reply.users))
      )


    this.mounting = import("./blocknote/blocknote").then(({ mountEditor }) =>
      this.isDestroyed ? null : mountEditor(this.el, {resolveUsers})
    )
  },

  destroyed() {
    this.isDestroyed = true
    this.mounting.then(unmount => unmount && unmount())
  },
}
