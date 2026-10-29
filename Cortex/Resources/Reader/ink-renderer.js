// Each wash is composited with the actual page, rather than painted as an
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
