// The JavaScript of Network.roc.

//// subscription my_app/network_changes
defineSubscription('my_app/network_changes', (args, host, emit) => {
  const tell = () => emit(new WireWriter().bool(navigator.onLine));
  addEventListener('online', tell);
  addEventListener('offline', tell);
  return () => {
    removeEventListener('online', tell);
    removeEventListener('offline', tell);
  };
});
