(() => {
  if(location.origin !== 'https://chatgpt.com' || window.top !== window) return;
  const action = async (action, expected = '') => {
    if(action === 'fixtureSignal' && location.pathname === '/fixture.html') return {signal:!!window.__fixtureSignal,duration:window.__fixtureDuration||0};

    const visible = e => e && e.getClientRects().length > 0;
    const buttons = label => Array.from(document.querySelectorAll('button')).filter(e => visible(e) && e.getAttribute('aria-label') === label);
    const one = label => { const a = buttons(label); return a.length === 1 ? a[0] : null; };
    const editor = () => {
      const a = Array.from(document.querySelectorAll('[contenteditable="true"][role="textbox"], #prompt-textarea, textarea')).filter(visible);
      const unique = [...new Set(a)]; return unique.length === 1 ? unique[0] : null;
    };
    const text = () => { const e = editor(); if (!e) return ''; return (e.tagName === 'TEXTAREA' ? e.value : e.innerText).trim(); };
    const click = label => {
      const e = one(label);
      if (!e || e.disabled || e.getAttribute('aria-disabled') === 'true') return {error:'ChatGPT control unavailable: ' + label + '. Check the connection window.'};
      e.click(); return {ok:true};
    };
    const temporary = !!one('Turn off temporary chat');
    const mic = one('Dictate');
    const ready = !!mic && !mic.disabled && mic.getAttribute('aria-disabled') !== 'true' && !!editor();
    if (action === 'state') {
      const a = window.__flowAudio?.state() || {};
      const login = Array.from(document.querySelectorAll('button,a')).some(e => visible(e) && ['Log in','Sign in'].includes(e.textContent.trim()));
      return {temporary, login, hasEditor:!!editor(), recording:!!one('Stop dictation') && !one('Stop dictation').disabled && !!one('Cancel dictation'), transcribing:!!one('Cancel transcription'), ready, text:text(), audioLevel:a.level || 0, audioQueued:a.queued || 0, audioFailed:!!a.failed, audioAttached:!!a.attached};
    }
    if (action === 'capture') { if (!window.__flowAudio) return {error:'The microphone bridge did not load. Reload the connection.'}; return await window.__flowAudio.begin(); }
    if (action === 'captureNative') { if (!window.__flowAudio) return {error:'The microphone bridge did not load. Reload the connection.'}; return await window.__flowAudio.begin(true); }
    if (action === 'feedAudio') { if (!window.__flowAudio?.state().active) return {error:'The audio renderer disconnected. Captured audio was not acknowledged.'}; await window.__flowAudio.push(expected); return {ok:true}; }
    if (action === 'playAudio') { window.__flowAudio?.play(); return {ok:true}; }
    if (action === 'freezeAudio') { window.__flowAudio?.stop(); return {ok:true}; }
    if (action === 'endAudio') { await window.__flowAudio?.end(); return {ok:true}; }
    if (action === 'prepare') {
      if (!one('Dictate') || !editor()) return {error:'Sign into ChatGPT and open a new empty chat with a Dictate button.'};
      if (text()) return {error:'The ChatGPT composer contains a draft. Flow will not overwrite it. Clear it yourself first.'};
      if (temporary) return {ok:true};
      return click('Temporary chat');
    }
    if (action === 'start') {
      if (!temporary) return {error:'Temporary Chat is not verified. Flow will not use a regular conversation automatically.'};
      if (text()) return {error:'The ChatGPT composer contains a draft. Clear it first.'};
      return click('Dictate');
    }
    if (action === 'stop') return click('Stop dictation');
    if (action === 'cancel') {
      for (const label of ['Cancel dictation','Starting dictation; click to cancel','Cancel transcription']) if (one(label)) return click(label);
      return {ok:true};
    }
    if (action === 'discard') {
      const e = editor();
      if (!e || text() !== expected) return {error:'The ChatGPT draft changed; it was preserved.'};
      e.focus();
      if (e.tagName === 'TEXTAREA') {
        Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype,'value').set.call(e,'');
        e.dispatchEvent(new Event('input',{bubbles:true}));
      } else { document.execCommand('selectAll',false); document.execCommand('delete',false); }
      if (text()) return {error:'ChatGPT kept the draft. Clear it before the next recording.'};
      return {ok:true};
    }
    return {error:'Unknown bridge action'};
    
  };
  window.chrome.webview.addEventListener('message', async event => {
    const request = event.data;
    if(!request || request.type !== 'flow-request' || typeof request.id !== 'number') return;
    try {
      const result = await action(request.action, request.expected || '');
      window.chrome.webview.postMessage({type:'flow-response', id:request.id, result});
    } catch(error) {
      window.chrome.webview.postMessage({type:'flow-response', id:request.id, result:{error:String(error.message || error)}});
    }
  });
})();
