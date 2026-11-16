(() => {
  if (location.origin !== 'https://chatgpt.com') return;
  const post = event => window.webkit.messageHandlers.floating.postMessage(event);
  // Only a pristine landing page can serve as the next empty conversation.
  // A single notification also covers paste, drops and toolbar interactions.
  let interaction = 0;
  function markUsed(event) {
    if (clearingDraft) return;
    const plain = event.target.closest?.(composerSelector) &&
      !['drop', 'change', 'submit'].includes(event.type) && !event.clipboardData?.files?.length;
    const next = plain ? 1 : 2;
    if (next <= interaction) return;
    interaction = next;
    post(plain ? 'textDraft' : 'landingUsed');
  }
  for (const type of ['input', 'change', 'pointerdown', 'click', 'drop', 'submit', 'paste']) {
    document.addEventListener(type, markUsed, true);
  }
  const composerSelector = '#prompt-textarea,#mobile-composer-prompt,main form textarea,main form [contenteditable="true"][role="textbox"]';
  const overlaySelector = 'dialog[open],[role="dialog"],[role="menu"],[role="listbox"],[aria-modal="true"]';
  const isShown = selector => [...document.querySelectorAll(selector)].some(el => el.getClientRects().length);
  const hasOverlay = () => isShown(overlaySelector + ',[aria-expanded="true"][aria-haspopup],[data-qc-form] [aria-expanded="true"],[data-state="open"][aria-haspopup]');
  const root = document.documentElement;
  let form, input, prior, compact = false, active = true, scheduled = false, observer;
  let freshEditor = true, clearingDraft = false;
  function clearRestoredDraft(editor) {
    if (!freshEditor || !compact || !active || location.pathname !== '/' || !editor) return;
    const textarea = editor instanceof HTMLTextAreaElement;
    if (!(textarea ? editor.value : editor.textContent)) return;
    clearingDraft = true;
    try {
      if (textarea) {
        Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value').set.call(editor, '');
      } else {
        editor.replaceChildren();
      }
      editor.dispatchEvent(new InputEvent('input', {bubbles:true, inputType:'deleteContentBackward'}));
    } finally {
      clearingDraft = false;
    }
  }
  for (const type of ['beforeinput', 'compositionstart', 'paste', 'drop']) {
    document.addEventListener(type, event => {
      const editor = event.target.closest?.(composerSelector);
      if (!editor || clearingDraft) return;
      clearRestoredDraft(editor);
      freshEditor = false;
    }, true);
  }
  document.addEventListener('input', event => {
    if (!clearingDraft && event.isTrusted && event.target.closest?.(composerSelector)) freshEditor = false;
  }, true);
  let lastMenuHeight = 0;
  let surface;
  function markComposerSurface(editor, owner) {
    if (!owner || (surface?.isConnected && surface.contains(editor))) return;
    surface?.removeAttribute('data-qc-surface');
    // Some layouts paint the form itself; others paint a rounded wrapper
    // inside the form. Tint that existing surface, leaving its content alone.
    for (let node = editor; node && owner.contains(node); node = node.parentElement) {
      if (parseFloat(getComputedStyle(node).borderTopLeftRadius) >= 16 &&
          node.getBoundingClientRect().width >= owner.clientWidth * 0.9) {
        sizeObserver.disconnect();
        surface = node;
        sizeObserver.observe(node);
        node.setAttribute('data-qc-surface', '');
        break;
      }
    }
  }
  let lastHeight;
  function measureComposer() {
    if (!active || !compact || !root.hasAttribute('data-qc-compact') || !surface?.isConnected) return;
    const height = surface.getBoundingClientRect().height;
    if (lastHeight !== height) {
      lastHeight = height;
      post({composerHeight:height});
    }
  }
  const sizeObserver = new ResizeObserver(measureComposer);
  window.addEventListener('resize', schedule);
  let allowFallback = false;
  let toolbarInteraction = false;
  function trackToolbar(event) {
    if (prior === 'ready') toolbarInteraction = compact && !!form?.contains(event.target) &&
      !event.target.closest(composerSelector);
  }
  document.addEventListener('pointerdown', trackToolbar, true);
  document.addEventListener('click', trackToolbar, true);
  setTimeout(() => { allowFallback = true; scan(); }, 8000);
  function render() {
    root.toggleAttribute('data-qc-compact', compact);
    root.toggleAttribute('data-qc-no-editor', compact && prior === 'full' && !form);
  }
  const turnSelector = '[data-message-author-role="user"],[data-turn="user"],[data-user-message-bubble]';
  const conversationPath = () => /^\/(?:uc|c)\/[^/]+/.test(location.pathname);
  let inConversation = conversationPath();
  let lastTurn = document.querySelectorAll(turnSelector).length;
  function scan() {
    scheduled = false;
    if (!active) return;
    input = [...document.querySelectorAll(composerSelector)].find(el => el.getClientRects().length);
    clearRestoredDraft(input);
    const count = compact ? document.querySelectorAll(turnSelector).length : lastTurn;
    const onThread = conversationPath();
    if (compact && onThread && (count > lastTurn || !inConversation)) post('sent');
    inConversation = onThread;
    lastTurn = count;
    if (input && !input.hasAttribute('data-qc-editor')) input.setAttribute('data-qc-editor', '');
    const next = input?.closest('form');
    if (form !== next) {
      form?.removeAttribute('data-qc-form');
      form = next;
      form?.setAttribute('data-qc-form', '');
    }
    markComposerSurface(input, form);
    measureComposer();
    const overlayOpen = hasOverlay();
    const needsFullPage = overlayOpen || !form && isShown('[data-testid="login-button"],[data-testid="login-button-mobile"]');
    if (!form && !needsFullPage && !allowFallback) return;
    const toolbarOpen = toolbarInteraction || form?.querySelector('[aria-expanded="true"]');
    const state = compact && form && overlayOpen && toolbarOpen ? 'tools' : needsFullPage || !form ? 'full' : 'ready';
    if (prior === 'tools' && state !== 'tools') toolbarInteraction = false;
    let menuHeight = 0;
    if (state === 'tools') {
      const popups = [...document.querySelectorAll(overlaySelector + ',[data-qc-popup]')];
      const tops = popups.filter(el => el.getClientRects().length).map(el => el.getBoundingClientRect().top);
      // Clip the stable viewport just above the highest open menu, including its shadow.
      menuHeight = Math.ceil(Math.min(470, Math.max(200, innerHeight - Math.min(innerHeight, ...tops) + 8)));
    }
    if (state !== prior || menuHeight !== lastMenuHeight) {
      prior = state;
      lastMenuHeight = menuHeight;
      render();
      post(menuHeight || state);
    }
    if (form && input.getAttribute('autocorrect') !== 'off') {
      input.setAttribute('autocorrect','off'); input.setAttribute('autocapitalize','off');
      input.setAttribute('writingsuggestions','false');
    }
  }
  function schedule() {
    if (!scheduled && active) { scheduled = true; requestAnimationFrame(scan); }
  }
  observer = new MutationObserver(records => {
    // The attachment chooser is a portal without a menu role. Only reveal a
    // newly mounted fixed popup while its own toolbar button is expanded.
    if (compact && toolbarInteraction && form?.querySelector('[aria-expanded="true"]')) {
      for (const record of records) {
        for (const node of record.addedNodes) {
          if (!(node instanceof Element)) continue;
          for (const el of [node, ...node.querySelectorAll('div')]) {
            if (getComputedStyle(el).position === 'fixed' && el !== form &&
                el.getBoundingClientRect().height > 24 && !el.contains(form)) {
              el.setAttribute('data-qc-popup', '');
              break;
            }
          }
        }
      }
    }
    // Streaming answer text is not a layout change; ignore mutations within turns.
    if (records.some(record => !record.target.parentElement?.closest('[data-message-author-role],[data-response-body],[data-user-message-bubble]'))) schedule();
  });
  function observe() {
    observer.observe(document.body, {childList:true,subtree:true,attributes:true,
      attributeFilter:['open','aria-expanded','aria-modal','hidden']});
  }
  // A reply may keep streaming after the panel is hidden. Report activity
  // without reading the text or running the layout scanner in the background.
  const replySelector = '[data-response-body],[data-message-author-role="assistant"]';
  let lastReplyNotice = -Infinity;
  const backgroundReplies = new MutationObserver(records => {
    if (performance.now() - lastReplyNotice < 1000) return;
    if (records.some(({target, addedNodes}) =>
      (target.nodeType === Node.ELEMENT_NODE ? target : target.parentElement)?.closest(replySelector) ||
      [...addedNodes].some(node => node.nodeType === Node.ELEMENT_NODE &&
        (node.matches(replySelector) || node.querySelector(replySelector))))) {
      lastReplyNotice = performance.now();
      post('replyUpdated');
    }
  });
  window.qcLayout = (small, visible, focus, trackChanges, resetDraft = false) => {
    if (resetDraft) { interaction = 0; freshEditor = true; }
    if (small && !compact && location.pathname === '/') freshEditor = true;
    if (small && !compact) lastTurn = document.querySelectorAll(turnSelector).length;
    if (small && visible && (!active || !compact)) lastHeight = undefined;
    active = visible; compact = small;
    observer.disconnect();
    backgroundReplies.disconnect();
    if (!active && !small) {
      lastReplyNotice = -Infinity;
      backgroundReplies.observe(document.body, {subtree:true, childList:true, characterData:true});
    }
    if (active && trackChanges) { observe(); scan(); }
    render();
    requestAnimationFrame(measureComposer);
    if (focus && active && prior === 'ready') input?.focus({preventScroll:true});
  };
  // The mobile textarea can treat Return as a line break. Activate its own
  // send control so the site's validation, attachments and submission run once.
  window.addEventListener('keydown', event => {
    if (event.key === 'Escape') {
      if (event.isComposing || event.keyCode === 229 || event.repeat) return;
      if (hasOverlay()) {
        const opener = form?.querySelector('button[aria-expanded="true"]:not([aria-haspopup])');
        if (opener && prior === 'tools') setTimeout(() => {
          if (opener.isConnected && opener.getAttribute('aria-expanded') === 'true') opener.click();
        }, 0);
        return;
      }
      event.preventDefault();
      event.stopImmediatePropagation();
      post('hide');
      return;
    }
    if (event.key !== 'Enter' || event.shiftKey || event.altKey || event.ctrlKey || event.metaKey ||
        event.isComposing || event.keyCode === 229 || prior !== 'ready') return;
    // The landing page and the conversation use different editors. The rich
    // editor may consume Enter before dispatching any click or submit event.
    const editor = event.target.closest?.(composerSelector);
    const owner = editor?.closest('form');
    if (!owner || !(editor.value ?? editor.textContent ?? '').trim()) return;
    if ((!compact && editor.id !== 'mobile-composer-prompt') || event.defaultPrevented) return;
    const buttons = owner.querySelectorAll('button[data-testid="send-button"],button[type="submit"],button#composer-submit-button');
    const send = [...buttons].find(button => !button.disabled && button.getAttribute('aria-disabled') !== 'true' &&
      button.dataset.testid !== 'stop-button' && button.getClientRects().length);
    if (!send) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    if (!event.repeat) {
      send.click();
      post('sent');
    }
  }, true);
  // Observe accepted sends without synthesizing keys or reading messages.
  document.addEventListener('submit', e => { if (e.target === form) post('sent'); }, true);
  document.addEventListener('click', e => {
    if (e.target.closest('[data-testid="create-new-chat-button"], [data-testid="new-chat-button"]')) post('newChat');
    if (form?.contains(e.target) && e.target.closest('button[type="submit"]:enabled,button[data-testid="send-button"],button#composer-submit-button:not([data-testid="stop-button"])')) post('sent');
  }, true);
  observe(); scan();
})();
