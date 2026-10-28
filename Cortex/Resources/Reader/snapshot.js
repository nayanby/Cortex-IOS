(() => {
  'use strict';
  const escape = text => String(text ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  function inline(raw, labels = true) {
    let text = String(raw ?? ''), prefix = '';
    if (labels) {
      const bold = text.match(/^\s*\*\*\s*([^:\n]{2,80}:)\s*\*\*/);
      const plain = text.match(/^\s*([^:\n]{2,80}:)/);
      const label = bold || (!text.trimStart().startsWith('**') ? plain : null);
      if (label) { prefix = '<span class="label">' + escape(label[1].trim()) + '</span>'; text = text.slice(label[0].length).trimStart(); if (text) prefix += ' '; }
    }
    let html = '', offset = 0;
    while (offset < text.length) {
      const open = text.indexOf('**', offset);
      if (open < 0) { html += escape(text.slice(offset)); break; }
      html += escape(text.slice(offset, open));
      const close = text.indexOf('**', open + 2);
      if (close < 0) { html += escape(text.slice(open)); break; }
      html += '<strong>' + escape(text.slice(open + 2, close)) + '</strong>'; offset = close + 2;
    }
    return prefix + html;
  }
  function points(holder, boundary = false) {
    const rows = holder.points || [], numbered = holder.numbered || []; let html = '';
    if (rows.length) {
      html += '<ul class="doc-list' + (boundary && !numbered.length ? ' ends-before-subheading' : '') + '">';
      for (const row of rows) {
        const p = typeof row === 'string' ? {text:row} : row, subs = p.subpoints || [];
        html += '<li class="doc-li' + (subs.length ? ' has-subs' : '') + '">' + inline(p.text);
        if (subs.length) html += '<ul class="doc-list">' + subs.map((s,i) => '<li class="doc-li sub' + (i === subs.length - 1 ? ' last-sub' : '') + '">' + inline(s) + '</li>').join('') + '</ul>';
        html += '</li>';
      }
      html += '</ul>';
    }
    if (numbered.length) {
      const last = rows[rows.length - 1], after = last?.subpoints?.length ? ' after-level-2' : rows.length ? ' after-level-1' : '';
      html += '<ol class="doc-list' + after + '">' + numbered.map(row => '<li class="doc-num">' + inline(String(row).replace(/^\s*\d+[.)]\s*/,'')) + '</li>').join('') + '</ol>';
    }
    return html;
  }
  function table(t) {
    let html = t.title ? '<div class="table-title">' + escape(t.title) + '</div>' : '';
    const headers = t.headers || [], rows = t.rows || [], columns = Math.max(headers.length, ...rows.map(r => r.length), 0);
    if (!columns) return html;
    html += '<div class="poster-table-box"><table class="poster-table"><tbody>';
    if (headers.length) html += '<tr>' + Array.from({length:columns},(_,i) => '<th>' + inline(headers[i] || '',false) + '</th>').join('') + '</tr>';
    html += rows.map((row,r) => '<tr' + (r%2 ? ' class="stripe"' : '') + '>' + Array.from({length:columns},(_,i) => '<td>' + inline(row[i] || '',false) + '</td>').join('') + '</tr>').join('');
    return html + '</tbody></table></div>';
  }
  window.cortexSnapshotType = async (delta = 0, line = 1.375, paragraph = 0.16) => {
    delta = Math.max(-1.5,Math.min(12,Number(delta)||0)); line = Math.max(1,Math.min(2,Number(line)||1.375)); paragraph = Math.max(0.08,Math.min(0.32,Number(paragraph)||0.16));
    const root = document.documentElement, body = Math.max(10.5,12.25+delta), leading = 1.5*line/1.375;
    const marker = Math.round((0.35*body-0.5)/body*1000)/1000, sub = Math.round((0.4*body-0.5)/body*1000)/1000;
    const values = {'--body-size':body+'pt','--table-size':(body-1)+'pt','--head-size':(15+delta)+'pt','--title-size':(17.25+delta)+'pt','--heading-line':1.125*line/1.375,'--paragraph-scale':paragraph/0.16,'--snapshot-gap':10*paragraph/0.16+'px','--body-lh':leading,'--bullet-marker-size':marker+'em','--sub-marker-size':sub+'em','--bullet-marker-top':((leading-marker)/2)+'em','--sub-marker-top':((leading-sub)/2)+'em'};
    for (const [key,value] of Object.entries(values)) root.style.setProperty(key,String(value));
    void document.body.offsetHeight; await document.fonts.ready;
    await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  };
  window.cortexLoadSnapshot = async (data, type = {}) => {
    const title = data.title ? '<div class="doc-title">' + escape(data.title) + '</div>' : '';
    const sections = (data.sections || []).map((section,index) => {
      const groups = section.groups || []; let html = points(section,groups.some(g => g.heading));
      groups.forEach((g,i) => { if (g.heading) html += '<div class="group-h">' + escape(g.heading) + '</div>'; html += points(g,groups.slice(i+1).some(next => next.heading)); });
      html += (section.tables || []).map(table).join('');
      return '<div class="section' + (index%2 ? ' even' : '') + '"><div class="section-head">' + escape(section.heading) + '</div><div class="section-body">' + html + '</div></div>';
    }).join('');
    document.getElementById('snapshot-root').innerHTML = title + sections;
    await window.cortexSnapshotType(type.delta,type.line,type.paragraph);
    await document.fonts.ready;
    return document.getElementById('snapshot-root').textContent;
  };
})();// Each wash is composited with the actual page, rather than painted as an
// opaque PencilKit marker on a separate native surface.
window.cortexRenderInk = function (strokes) {
  const ns = 'http://www.w3.org/2000/svg';
  for (const name of ['wash', 'pen']) {
    const id = 'cortex-ink-' + name;
    let svg = document.getElementById(id);
    if (!svg) {
      svg = document.createElementNS(ns, 'svg'); svg.id = id;
      Object.assign(svg.style, {position:'absolute',left:'0',top:'0',pointerEvents:'none',zIndex:name==='wash'?'20':'21',overflow:'visible',mixBlendMode:name==='wash'?'multiply':'normal'});
      document.body.appendChild(svg);
    }
    const width = document.documentElement.clientWidth;
    const height = document.getElementById('paper').scrollHeight;
    svg.setAttribute('width', width); svg.setAttribute('height', height);
    svg.setAttribute('viewBox', `0 0 ${width} ${height}`);
    svg.replaceChildren();
    for (const stroke of strokes.filter(s => Boolean(s.wash) === (name === 'wash'))) {
      if (!stroke.points?.length) continue;
      const path = document.createElementNS(ns,'path');
      path.setAttribute('d',stroke.points.map((p,i)=>(i?'L':'M')+Number(p[0]).toFixed(2)+' '+Number(p[1]).toFixed(2)).join(' '));
      path.setAttribute('fill','none');path.setAttribute('stroke',stroke.color);
      path.setAttribute('stroke-width',stroke.width);path.setAttribute('stroke-linecap',stroke.underliner?'butt':'round');path.setAttribute('stroke-linejoin','round');
      svg.appendChild(path);
    }
  }
};
