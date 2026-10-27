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
  window.cortexLoadDocument = async (base64, savedProgress = 0, typography = {delta:0, line:1.4375, paragraph:0.16}) => {
    window.cortexReleaseImages();
    const bytes = Uint8Array.from(atob(base64), c => c.charCodeAt(0));
    const doc = new window.CortexDocx(bytes);
    await doc.init();
    const root = await doc.render();
    document.getElementById('paper').replaceChildren(root);
    window.cnlIndentHeadingPrefixes?.(root);
    window.cnlAlignBulletMarkers?.(root);
    await window.cortexSetTypography(typography.delta, typography.line, typography.paragraph);
    headings = [...root.querySelectorAll('.doc-p.h1,.doc-p.h2,.doc-p.h3,.doc-p.h4')];
    // Force style resolution, then load the faces used by the note. A previously
    // resolved fonts.ready promise alone can precede layout of newly inserted text.
    void root.offsetHeight;
    await Promise.all([
      document.fonts.load('400 16px "Lato"'),
      document.fonts.load('700 16px "Lato"'),
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
  const originalLayout = new WeakMap();
  let typographySerial = 0;
  window.cortexSetTypography = async (delta, line, paragraph) => {
    delta = Number(delta); line = Number(line); paragraph = Number(paragraph);
    if (!Number.isFinite(delta) || delta < -1.5 || delta > 1.5 ||
        !Number.isFinite(line) || line < 1 || line > 2 ||
        !Number.isFinite(paragraph) || paragraph < 0.08 || paragraph > 0.33) return false;
    const fraction = progress();
    const serial = ++typographySerial;
    const elements = [...document.querySelectorAll('#paper *')].filter(el => !el.closest('svg, math') && !el.matches('mark[data-cortex-highlight]'));
    // Capture the whole tree before changing any inherited styles.
    for (const el of elements) {
      if (!originalSizes.has(el)) {
        const computed = getComputedStyle(el);
        originalSizes.set(el, parseFloat(computed.fontSize));
        originalLayout.set(el, {line: parseFloat(computed.lineHeight), top: parseFloat(computed.marginTop), bottom: parseFloat(computed.marginBottom)});
      }
    }
    const headingSelector = '.h1,.h2,.h3,.h4,.boldside1,.boldside2,.boldside3,.word-h1,.word-h2,.word-h3,.word-h4';
    for (const el of elements) {
      const original = originalSizes.get(el), layout = originalLayout.get(el);
      const inTable = !!el.closest('table');
      const size = inTable ? Math.max(14, 17 - 2 / 3 + delta * 4 / 3) - 4 / 3 : Math.max(4, original + delta * 4 / 3);
      if (!Number.isFinite(size)) continue;
      const heading = !!el.closest(headingSelector);
      el.style.setProperty('font-size', size + 'px', 'important');
      const leading = inTable ? size * 1.3 : size * (heading ? 1.125 : 1.5) * line / 1.5;
      el.style.setProperty('line-height', leading + 'px', 'important');
      if (el.classList.contains('doc-list')) el.style.setProperty('--cnl-list-first-line-height', leading + 'px');
      const isParagraph = el.classList.contains('doc-p'), isBlock = el.classList.contains('doc-block');
      if (inTable && isParagraph) {
        el.style.setProperty('margin-top', '0', 'important');
        el.style.setProperty('margin-bottom', '2pt', 'important');
      } else if ((isParagraph || isBlock) && !heading) {
        el.style.setProperty('margin-top', '0', 'important');
        el.style.setProperty('margin-bottom', '0', 'important');
        if (isBlock) {
          const list = el.querySelector(':scope > .doc-list, :scope > .doc-p.doc-list');
          el.style.setProperty('padding-top', (list ? 0 : 0.05 * size) + 'px', 'important');
          el.style.setProperty('padding-bottom', (list ? 6 : 14) * paragraph / 0.16 + 'px', 'important');
        } else {
          const inBlock = el.parentElement?.classList.contains('doc-block');
          const added = Number.isFinite(layout.line) ? layout.line * size / original * paragraph : 0;
          el.style.setProperty('margin-top', (inBlock ? 0 : added) + 'px', 'important');
          el.style.setProperty('margin-bottom', (inBlock ? 0 : 14 * paragraph / 0.16) + 'px', 'important');
        }
      } else if (layout) {
        if (layout.top > 0) el.style.setProperty('margin-top', layout.top * (1 + paragraph) + 'px', 'important');
        if (layout.bottom > 0) el.style.setProperty('margin-bottom', layout.bottom * (1 + paragraph) + 'px', 'important');
      }
    }
    void document.getElementById('paper').offsetHeight;
    await document.fonts.ready;
    await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    if (serial === typographySerial) window.scrollTo(0, fraction * Math.max(0, document.documentElement.scrollHeight - innerHeight));
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
        mark.style.setProperty('font-size', 'inherit', 'important');
        mark.style.setProperty('line-height', 'inherit', 'important');
        mark.style.setProperty('font-family', 'inherit', 'important');
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
