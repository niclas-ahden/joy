// The system clipboard, for the platform's Clipboard module.
//
// Sections as in media.js: an app's runtime.js holds the ones its wasm uses.

//// helper write_clipboard
// A failure is thrown with the name the platform tells it apart by: the
// browser's own NotAllowedError, or SecurityError and NotSupportedError for
// a page that has no clipboard to write to.
async function writeClipboard(text) {
  const clipboard = globalThis.navigator?.clipboard;
  if (typeof clipboard?.writeText !== 'function') {
    const insecure = globalThis.isSecureContext === false;
    const err = new Error(insecure ? 'the clipboard needs HTTPS or localhost' : 'this browser has no clipboard API');
    err.name = insecure ? 'SecurityError' : 'NotSupportedError';
    throw err;
  }
  await clipboard.writeText(text);
}

//// op joy/clipboard/write_text needs write_clipboard
defineOperation('joy/clipboard/write_text', (args) => writeClipboard(args.str()));

//// op joy/clipboard/write_text_of needs write_clipboard
// An element that is not there fails as NotFoundError.
defineOperation('joy/clipboard/write_text_of', async (args, host) => {
  const selector = args.str();
  const text = host.dom.textOf(selector);
  if (text === null) {
    const err = new Error(`nothing on the page matches "${selector}"`);
    err.name = 'NotFoundError';
    throw err;
  }
  await writeClipboard(text);
});
