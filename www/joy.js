// Joy's loader. A page loads it as a module, and it mounts every bundle root
// on the page:
//
//   <div data-joy-bundle="Checkout/cart" data-joy-flags="..."></div>
//   <script type="module" src="/joy.js"></script>
//
// data-joy-bundle is the bundle's id, its path below client/ without the
// extension. Its wasm is <id>/app.wasm beside this file, unless the root
// names another URL in data-joy-wasm, as a build does for hashed names.
// data-joy-flags is the string the app's init receives.
//
// A root with children holds the server's first view, and the app hydrates
// it instead of rendering it again.
//
// Before a root mounts, `joy:mount` bubbles from it, and the page's own
// script can set `detail.setup`, a function that gets the app before init
// runs, to wire ports. Once mounted, the root has the app in `root.joy` and
// the attribute data-joy-mounted, and `joy:mounted` bubbles with the app.
import { mount } from './runtime.js';

async function mountRoot(root) {
  const bundle = root.dataset.joyBundle;
  const detail = { bundle, setup: null };
  root.dispatchEvent(new CustomEvent('joy:mount', { bubbles: true, detail }));
  const options = {
    wasm: root.dataset.joyWasm ?? new URL(`./${bundle}/app.wasm`, import.meta.url).href,
    root,
    flags: root.dataset.joyFlags ?? '',
    hydrate: root.hasChildNodes(),
  };
  if (detail.setup) options.setup = detail.setup;
  const app = await mount(options);
  root.joy = app;
  root.setAttribute('data-joy-mounted', '');
  root.dispatchEvent(new CustomEvent('joy:mounted', { bubbles: true, detail: { bundle, app } }));
}

// One root that fails to mount leaves the others running.
for (const root of document.querySelectorAll('[data-joy-bundle]')) {
  mountRoot(root).catch((error) => {
    console.error(`Joy: the bundle ${root.dataset.joyBundle} did not mount`, error);
  });
}
