/* Native calls pass data through named WebKit arguments, never executable strings. */
(() => {
  'use strict';
  let headings = [];
  let scrollTimer;
  function progress() {
    const max = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
    return max ? Math.min(1, Math.max(0, window.scrollY / max)) : 0;
  }
  function reportProgress() {
    window.webkit?.messageHandlers?.readingProgress?.postMessage(progress());
  }
  window.cortexLoadDocument = async (base64, savedProgress = 0) => {
    window.cortexReleaseImages();
    const bytes = Uint8Array.from(atob(base64), c => c.charCodeAt(0));
    const doc = new window.CortexDocx(bytes);
    await doc.init();
    const root = await doc.render();
    document.getElementById('paper').replaceChildren(root);
    window.cnlIndentHeadingPrefixes?.(root);
    window.cnlAlignBulletMarkers?.(root);
    headings = [...root.querySelectorAll('.doc-p.h1,.doc-p.h2,.doc-p.h3,.doc-p.h4')];
    // Force style resolution, then load the faces used by the note. A previously
    // resolved fonts.ready promise alone can precede layout of newly inserted text.
    void root.offsetHeight;
    await Promise.all([
      document.fonts.load('400 16px "Source Sans Pro"'),
      document.fonts.load('700 16px "Source Sans Pro"'),
      document.fonts.load('400 16px "Averia Serif Libre"'),
      document.fonts.load('700 23px "Averia Serif Libre"')
    ]);
    await document.fonts.ready;
    await Promise.all([...root.querySelectorAll('img')].map(img => img.complete ? null :
      new Promise(resolve => { img.onload = resolve; img.onerror = resolve; })));
    await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    const fraction = Math.min(1, Math.max(0, Number(savedProgress) || 0));
    window.scrollTo(0, fraction * Math.max(0, document.documentElement.scrollHeight - window.innerHeight));
    return headings.map((node, index) => ({index, text: node.textContent.trim(), level: Number(node.dataset.headingLevel) || 1}));
  };
  window.cortexJumpToHeading = index => {
    if (!Number.isInteger(index) || !headings[index]) return false;
    headings[index].scrollIntoView({block:'start', behavior:'auto'});
    reportProgress();
    return true;
  };
  window.cortexReadingProgress = progress;
  window.addEventListener('scroll', () => {
    clearTimeout(scrollTimer);
    scrollTimer = setTimeout(reportProgress, 250);
  }, {passive:true});
})();
