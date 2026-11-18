// The JavaScript of Share.roc.

//// effect my_app/share_link
defineEffect('my_app/share_link', async (args) => {
  const title = args.str();
  const url = args.str();
  if (!navigator.share) {
    throw new DOMException('This browser has no share sheet', 'NotSupportedError');
  }
  await navigator.share({ title, url });
});
