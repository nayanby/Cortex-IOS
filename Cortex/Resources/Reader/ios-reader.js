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
  const originalSizes = new WeakMap();
  window.cortexSetTypography = (delta, line, paragraph) => {
    delta = Number(delta); line = Number(line); paragraph = Number(paragraph);
    if (!Number.isFinite(delta) || delta < -1.5 || delta > 1.5 ||
        !Number.isFinite(line) || line < 1 || line > 2 ||
        !Number.isFinite(paragraph) || paragraph < 0.08 || paragraph > 0.33) return false;
    const fraction = progress();
    const elements = [...document.querySelectorAll('#paper *')].filter(el => !el.closest('svg, math'));
    // Capture the whole tree before changing any inherited styles.
    for (const el of elements) {
      if (!originalSizes.has(el)) originalSizes.set(el, parseFloat(getComputedStyle(el).fontSize));
    }
    for (const el of elements) {
      const original = originalSizes.get(el);
      if (Number.isFinite(original)) el.style.fontSize = Math.max(4, original + delta * 96 / 72) + 'px';
    }
    for (const el of document.querySelectorAll('#paper .doc-p')) {
      el.style.lineHeight = String(line);
      el.style.marginBottom = paragraph + 'em';
    }
    window.scrollTo(0, fraction * Math.max(0, document.documentElement.scrollHeight - innerHeight));
    return true;
  };
  window.cortexRestoreProgress = fraction => {
    fraction = Math.max(0, Math.min(1, Number(fraction) || 0));
    window.scrollTo(0, fraction * Math.max(0, document.documentElement.scrollHeight - innerHeight));
    reportProgress();
  };
  let highlights = [];
  function textNodes() {
    const walker = document.createTreeWalker(document.getElementById('paper'), NodeFilter.SHOW_TEXT);
    const nodes = []; let node;
    while ((node = walker.nextNode())) nodes.push(node);
    return nodes;
  }
  window.cortexApplyHighlights = records => {
    const paper = document.getElementById('paper');
    for (const mark of paper.querySelectorAll('mark[data-cortex-highlight]')) mark.replaceWith(...mark.childNodes);
    paper.normalize();
    const fullText = paper.textContent;
    highlights = (Array.isArray(records) ? records : []).slice(0, 250).filter(record =>
      Number.isInteger(record.start) && Number.isInteger(record.end) && record.start >= 0 &&
      record.end > record.start && record.end - record.start <= 20000 &&
      typeof record.quote === 'string' && fullText.slice(record.start, record.end) === record.quote);
    for (const record of highlights) {
      let offset = 0;
      for (const node of textNodes()) {
        const start = Math.max(0, record.start - offset), end = Math.min(node.length, record.end - offset);
        offset += node.length;
        if (end <= start) continue;
        const range = document.createRange(); range.setStart(node, start); range.setEnd(node, end);
        const mark = document.createElement('mark'); mark.dataset.cortexHighlight = 'true';
        mark.style.backgroundColor = record.color === 'green' ? '#c7f2ce' : '#fff19a';
        mark.style.color = 'inherit';
        range.surroundContents(mark);
      }
    }
    return highlights;
  };
  window.cortexHighlightSelection = color => {
    const selection = window.getSelection(), paper = document.getElementById('paper');
    if (!selection || !selection.rangeCount || selection.isCollapsed) return null;
    const range = selection.getRangeAt(0);
    if (!paper.contains(range.startContainer) || !paper.contains(range.endContainer)) return null;
    const preceding = document.createRange(); preceding.selectNodeContents(paper); preceding.setEnd(range.startContainer, range.startOffset);
    const start = preceding.toString().length, quote = range.toString();
    if (!quote.length || quote.length > 20000 || highlights.length >= 250) return null;
    const records = [...highlights, {start, end: start + quote.length, quote, color: color === 'green' ? 'green' : 'yellow'}];
    selection.removeAllRanges();
    return window.cortexApplyHighlights(records);
  };
  window.cortexReadingProgress = progress;
  window.addEventListener('scroll', () => {
    clearTimeout(scrollTimer);
    scrollTimer = setTimeout(reportProgress, 250);
  }, {passive:true});
})();
