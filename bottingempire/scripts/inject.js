'use strict';

const script = document.createElement('script');
script.dataset.hidden = document.hidden;
script.addEventListener('state', () => {
  script.dataset.hidden = document.hidden;
});

script.textContent = `{
  const script = document.currentScript;
  const isFirefox = /Firefox/.test(navigator.userAgent) || typeof InstallTrigger !== 'undefined';

  const block = e => {
    e.preventDefault();
    e.stopPropagation();
    e.stopImmediatePropagation();
  };

  /* visibility */
  Object.defineProperty(document, 'visibilityState', {
    get() {
      return 'visible';
    }
  });
  if (isFirefox === false) {
    Object.defineProperty(document, 'webkitVisibilityState', {
      get() {
        return 'visible';
      }
    });
  }
  document.addEventListener('visibilitychange', e => {
    script.dispatchEvent(new Event('state'));
    if (script.dataset.visibility !== 'false') {
      return block(e);
    }
  }, true);
  document.addEventListener('webkitvisibilitychange', e => script.dataset.visibility !== 'false' && block(e), true);
  window.addEventListener('pagehide', e => script.dataset.visibility !== 'false' && block(e), true);

  /* hidden */
  Object.defineProperty(document, 'hidden', {
    get() {
      return false;
    }
  });
  Object.defineProperty(document, isFirefox ? 'mozHidden' : 'webkitHidden', {
    get() {
      return false;
    }
  });

  /* focus */
  document.addEventListener('hasFocus', e => script.dataset.focus !== 'false' && block(e), true);
  document.__proto__.hasFocus = new Proxy(document.__proto__.hasFocus, {
    apply(target, self, args) {
      if (script.dataset.focus !== 'false') {
        return true;
      }
      return Reflect.apply(target, self, args);
    }
  });

  /* blur */
  const onblur = e => {
    if (script.dataset.blur !== 'false') {
      if (e.target === document || e.target === window) {
        return block(e);
      }
    }
  };
  document.addEventListener('blur', onblur, true);
  window.addEventListener('blur', onblur, true);

  /* mouse */
  window.addEventListener('mouseleave', e => {
    if (script.dataset.mouseleave !== 'false') {
      if (e.target === document || e.target === window) {
        return block(e);
      }
    }
  }, true);

  /* requestAnimationFrame */
  let lastTime = 0;
  window.requestAnimationFrame = new Proxy(window.requestAnimationFrame, {
    apply(target, self, args) {
      if (script.dataset.hidden === 'true') {
        const currTime = Date.now();
        const timeToCall = Math.max(0, 16 - (currTime - lastTime));
        const id = window.setTimeout(function() {
          args[0](performance.now());
        }, timeToCall);
        lastTime = currTime + timeToCall;
        return id;
      }
      else {
        return Reflect.apply(target, self, args);
      }
    }
  });
  window.cancelAnimationFrame = new Proxy(window.cancelAnimationFrame, {
    apply(target, self, args) {
      if (script.dataset.hidden === 'true') {
        clearTimeout(args[0]);
      }
      return Reflect.apply(target, self, args);
    }
  });

}`;
document.documentElement.appendChild(script);
script.remove();
