// The JavaScript of Locale.roc.

//// effect my_app/locale_get
defineEffect('my_app/locale_get', () => {
  const timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone;
  return new WireWriter().str(navigator.language).str(timeZone);
});
