// Extracted from Cortex Consumer; see android-reader-provenance.json.
const NS = {
  w:'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
  r:'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
  a:'http://schemas.openxmlformats.org/drawingml/2006/main',
  wp:'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing',
  pic:'http://schemas.openxmlformats.org/drawingml/2006/picture',
  rel:'http://schemas.openxmlformats.org/package/2006/relationships'
};

const $ = s => document.querySelector(s);
const qsa = (el, s) => Array.from(el.querySelectorAll(s));
const first = (el, s) => el ? el.querySelector(s) : null;
const attr = (el, name, ns=NS.w) => el ? (el.getAttributeNS(ns,name) ?? el.getAttribute('w:'+name) ?? el.getAttribute(name)) : null;
const parseXml = txt => new DOMParser().parseFromString(txt, 'application/xml');
const esc = s => (s ?? '').replace(/[&<>"']/g, m => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));
const clamp = (v,a,b) => Math.max(a,Math.min(b,v));
const twipToPx = t => Number(t||0) * 96 / 1440;
const halfPtToPt = v => Number(v||0)/2;
const emuToPx = v => Number(v||0) * 96 / 914400;

let activeObserver = null;
let objectUrls = [];

function revokeObjectUrls(){
  objectUrls.forEach(u=>URL.revokeObjectURL(u));
  objectUrls=[];
}

function directChild(el, localName){
  return el ? Array.from(el.children).find(n => n.localName === localName) || null : null;
}
function directChildren(el, localName){
  return el ? Array.from(el.children).filter(n => n.localName === localName) : [];
}
function directDesc(el, path){
  let cur=el;
  for(const name of path){ cur=directChild(cur,name); if(!cur) return null; }
  return cur;
}
function childVal(el, name){
  const n=directChild(el,name);
  return n ? attr(n,'val') : null;
}
function normalizeStyle(s){ return String(s||'').replace(/[\s_-]+/g,'').toLowerCase(); }



function keepSidebarExpandedAfterNavigation(){
  const sidebar=document.querySelector('.sidebar');
  if(sidebar){
    sidebar.classList.remove('collapsed');
    sidebar.classList.remove('is-collapsed');
  }
  document.body.classList.remove('sidebar-collapsed');

  // Do not alter folder/document tree expansion states.
  // Navigation clicks should only select/scroll, never fold the tree.
}

function scrollDocumentToTop(){
  const paper=document.querySelector('#paper');
  const scrollCandidates=[
    document.querySelector('.main'),
    document.querySelector('.content'),
    document.querySelector('.document-pane'),
    document.querySelector('.viewer'),
    document.scrollingElement
  ].filter(Boolean);

  // Scroll the actual document container if it is independently scrollable.
  for(const el of scrollCandidates){
    try{
      if(el===document.scrollingElement){
        window.scrollTo({top:0,left:0,behavior:'auto'});
      }else if(el.scrollHeight>el.clientHeight){
        el.scrollTo({top:0,left:0,behavior:'auto'});
      }
    }catch{}
  }

  // Ensure the rendered paper itself is aligned to the top of the viewport.
  if(paper){
    try{
      paper.scrollIntoView({block:'start',inline:'nearest',behavior:'auto'});
    }catch{}
  }
}

class DocxPrototype {
  constructor(file){
    this.file=file;
    this.zip=null;
    this.document=null;
    this.styles=null;
    this.numbering=null;
    this.rels=null;
    this.theme=null;
    this.styleMap=new Map();
    this.numberingMap=new Map();
    this.abstractMap=new Map();
    this.relMap=new Map();
    this.themeColors={};
    this.counters={};
    this.report={h1:0,h2:0,h3:0,h4:0,bs1:0,bs2:0,bs3:0,lists:0,tables:0,images:0,removedEmpty:0,removedStrips:0};
  }

  async init(){
    this.zip = await JSZip.loadAsync(this.file);
    const req = async p => {
      const f=this.zip.file(p);
      if(!f) throw new Error('Missing '+p);
      return parseXml(await f.async('string'));
    };
    const opt = async p => {
      const f=this.zip.file(p);
      return f ? parseXml(await f.async('string')) : null;
    };

    [this.document,this.styles,this.numbering,this.rels,this.theme] = await Promise.all([
      req('word/document.xml'),
      opt('word/styles.xml'),
      opt('word/numbering.xml'),
      opt('word/_rels/document.xml.rels'),
      opt('word/theme/theme1.xml')
    ]);

    this.parseTheme();
    this.parseRelationships();
    this.parseStyles();
    this.parseNumbering();
  }

  parseTheme(){
    if(!this.theme) return;
    const scheme=first(this.theme,'a\\:clrScheme, clrScheme');
    if(!scheme) return;
    for(const c of Array.from(scheme.children)){
      const key=c.localName;
      const valNode=Array.from(c.children)[0];
      if(!valNode) continue;
      const val=valNode.getAttribute('val') || valNode.getAttribute('lastClr');
      if(val) this.themeColors[key]=val.replace('#','');
    }
  }

  parseRelationships(){
    if(!this.rels) return;
    for(const rel of qsa(this.rels,'Relationship')){
      this.relMap.set(rel.getAttribute('Id'), rel.getAttribute('Target'));
    }
  }

  parseStyles(){
    if(!this.styles) return;
    for(const s of qsa(this.styles,'w\\:style, style')){
      const id=attr(s,'styleId');
      if(!id) continue;
      const nameNode=directChild(s,'name');
      const based=directChild(s,'basedOn');
      this.styleMap.set(id,{
        id,
        type:attr(s,'type'),
        name:nameNode ? attr(nameNode,'val') : id,
        basedOn:based ? attr(based,'val') : null,
        pPr:directChild(s,'pPr'),
        rPr:directChild(s,'rPr'),
        raw:s,
        resolved:null
      });
    }
  }

  parseNumbering(){
    if(!this.numbering) return;
    for(const a of qsa(this.numbering,'w\\:abstractNum, abstractNum')){
      const id=attr(a,'abstractNumId');
      const levels=new Map();
      for(const lvl of directChildren(a,'lvl')){
        const ilvl=Number(attr(lvl,'ilvl')||0);
        const numFmt=childVal(lvl,'numFmt')||'bullet';
        const lvlText=childVal(lvl,'lvlText')||'';
        const start=Number(childVal(lvl,'start')||1);
        const pPr=directChild(lvl,'pPr');
        const rPr=directChild(lvl,'rPr');
        levels.set(ilvl,{ilvl,numFmt,lvlText,start,pPr,rPr});
      }
      this.abstractMap.set(id,{id,levels});
    }
    for(const n of qsa(this.numbering,'w\\:num, num')){
      const id=attr(n,'numId');
      const abs=directChild(n,'abstractNumId');
      if(id && abs) this.numberingMap.set(id, attr(abs,'val'));
    }
  }

  resolveStyle(styleId, seen=new Set()){
    if(!styleId || seen.has(styleId)) return {p:{},r:{}};
    const s=this.styleMap.get(styleId);
    if(!s) return {p:{},r:{}};
    if(s.resolved) return s.resolved;
    seen.add(styleId);
    let base={p:{},r:{}};
    if(s.basedOn) base=this.resolveStyle(s.basedOn,seen);
    const resolved={
      p:{...base.p,...this.parsePPr(s.pPr)},
      r:{...base.r,...this.parseRPr(s.rPr)}
    };
    s.resolved=resolved;
    return resolved;
  }

  semanticStyle(styleId){
    const s=this.styleMap.get(styleId);
    const n=normalizeStyle(s?.name || styleId);
    const idn=normalizeStyle(styleId);

    const headingMap = [
      [1,['heading1','h1']],
      [2,['heading2','h2']],
      [3,['heading3','h3']],
      [4,['heading4','h4']]
    ];
    for(const [level,names] of headingMap){
      if(names.includes(n) || names.includes(idn)) return {kind:'heading',level};
    }
    if(n==='boldside1' || idn==='boldside1') return {kind:'boldside',level:1};
    if(n==='boldside2' || idn==='boldside2') return {kind:'boldside',level:2};
    if(n==='boldside3' || idn==='boldside3') return {kind:'boldside',level:3};
    return {kind:'body',level:0};
  }


  semanticStyleForParagraph(p,merged){
    // Normal path: genuine Word paragraph style wins.
    const normal=this.semanticStyle(merged.styleId);
    if(normal.kind!=='body') return normal;

    // Do not reinterpret a paragraph that already has some other pStyle.
    // This fallback is only for flattened DOCX exports where w:pStyle is absent.
    if(merged.styleId) return normal;

    const pPr=directChild(p,'pPr');
    if(!pPr) return normal;

    const directP=this.parsePPr(pPr);

    const runs=directChildren(p,'r').filter(r=>
      qsa(r,'w\\:t, t').some(t=>(t.textContent||'').trim())
    );
    if(!runs.length) return normal;

    // Use the first textual run as the paragraph's direct-format signature.
    const directR=this.parseRPr(directChild(runs[0],'rPr'));

    // A flattened structural heading normally carries at least one of these:
    // paragraph shading or a paragraph border. Requiring a structural marker
    // prevents ordinary bold/capitalized body text from being promoted.
    const hasStructuralMarker=!!(
      directP.background ||
      directP.borderTop ||
      directP.borderRight ||
      directP.borderBottom ||
      directP.borderLeft
    );
    if(!hasStructuralMarker) return normal;

    const sameColor=(a,b)=>
      !!a && !!b && String(a).toLowerCase()===String(b).toLowerCase();

    const borderPresent=o=>!!(
      o?.borderTop || o?.borderRight || o?.borderBottom || o?.borderLeft
    );

    const candidates=[];

    for(const [sid,st] of this.styleMap.entries()){
      if(st.type!=='paragraph') continue;

      const sem=this.semanticStyle(sid);
      if(sem.kind==='body') continue;
      if(sem.kind==='heading' && sem.level>4) continue;
      if(sem.kind==='boldside' && sem.level>3) continue;

      const resolved=this.resolveStyle(sid);
      const sp=resolved.p || {};
      const sr=resolved.r || {};

      let score=0;
      let strongStructural=false;

      // Exact paragraph fill is a very strong signature.
      if(directP.background && sp.background){
        if(sameColor(directP.background,sp.background)){
          score+=8;
          strongStructural=true;
        }
      }

      // Presence of a paragraph border plus matching run color is also strong.
      const db=borderPresent(directP);
      const sb=borderPresent(sp);
      if(db && sb){
        score+=3;
        if(directR.color && sr.color && sameColor(directR.color,sr.color)){
          strongStructural=true;
        }
      }

      if(directR.bold===true && sr.bold===true) score+=2;
      if(directR.caps===true && sr.caps===true) score+=2;

      if(directR.color && sr.color && sameColor(directR.color,sr.color)) score+=3;

      if(directR.fontSizePt && sr.fontSizePt){
        const diff=Math.abs(directR.fontSizePt-sr.fontSizePt);
        if(diff<=0.5) score+=3;
        else if(diff<=2) score+=1;
      }

      if(strongStructural && score>=8){
        candidates.push({sem,score});
      }
    }

    if(!candidates.length) return normal;

    candidates.sort((a,b)=>b.score-a.score);
    const best=candidates[0];

    // Avoid ambiguous promotion if two different semantic levels tie.
    if(candidates.length>1 &&
       candidates[1].score===best.score &&
       (candidates[1].sem.kind!==best.sem.kind ||
        candidates[1].sem.level!==best.sem.level)){
      return normal;
    }

    return {...best.sem,flattened:true};
  }

  applyThemeTintShade(hex, tintHex, shadeHex){
    if(!hex) return null;
    let h=hex.replace('#','');
    if(h.length!==6) return '#'+h;
    let rgb=[0,2,4].map(i=>parseInt(h.slice(i,i+2),16));
    if(shadeHex){
      const f=parseInt(shadeHex,16)/255;
      rgb=rgb.map(c=>Math.round(c*f));
    }
    if(tintHex){
      const f=parseInt(tintHex,16)/255;
      rgb=rgb.map(c=>Math.round(c+(255-c)*f));
    }
    return '#'+rgb.map(c=>clamp(c,0,255).toString(16).padStart(2,'0')).join('');
  }

  parseColor(node){
    if(!node) return null;
    let v=attr(node,'val');
    if(v && v !== 'auto') return '#'+v.replace('#','');
    const theme=attr(node,'themeColor');
    if(theme && this.themeColors[theme]){
      return this.applyThemeTintShade(this.themeColors[theme], attr(node,'themeTint'), attr(node,'themeShade'));
    }
    return null;
  }

  parseShading(node){
    if(!node) return null;
    const fill=attr(node,'fill');
    if(fill && fill!=='auto') return '#'+fill.replace('#','');
    const theme=attr(node,'themeFill');
    if(theme && this.themeColors[theme]){
      return this.applyThemeTintShade(this.themeColors[theme], attr(node,'themeFillTint'), attr(node,'themeFillShade'));
    }
    return null;
  }

  parseBorderSide(n){
    if(!n) return null;
    const val=attr(n,'val');
    if(!val || val==='nil' || val==='none') return null;
    const color=this.parseColor(n) || '#000000';
    const sz=Number(attr(n,'sz')||8)/8;
    const styleMap={single:'solid',double:'double',dotted:'dotted',dashSmallGap:'dashed',dashed:'dashed',dotDash:'dashed',dotDotDash:'dashed'};
    return `${Math.max(.5,sz)}pt ${styleMap[val]||'solid'} ${color}`;
  }

  parsePPr(pPr){
    const out={};
    if(!pPr) return out;
    const jc=directChild(pPr,'jc');
    if(jc) out.align=attr(jc,'val');
    const ind=directChild(pPr,'ind');
    if(ind){
      if(attr(ind,'left')!=null) out.indentLeft=twipToPx(attr(ind,'left'));
      if(attr(ind,'right')!=null) out.indentRight=twipToPx(attr(ind,'right'));
      if(attr(ind,'firstLine')!=null) out.firstLine=twipToPx(attr(ind,'firstLine'));
      if(attr(ind,'hanging')!=null) out.hanging=twipToPx(attr(ind,'hanging'));
    }
    const shd=directChild(pPr,'shd');
    if(shd){
      const bg=this.parseShading(shd);
      if(bg) out.background=bg;
    }
    const bdr=directChild(pPr,'pBdr');
    if(bdr){
      for(const side of ['top','right','bottom','left']){
        const bs=this.parseBorderSide(directChild(bdr,side));
        if(bs) out['border'+side[0].toUpperCase()+side.slice(1)]=bs;
      }
    }
    const numPr=directChild(pPr,'numPr');
    if(numPr){
      const il=directChild(numPr,'ilvl'), ni=directChild(numPr,'numId');
      if(il) out.ilvl=Number(attr(il,'val')||0);
      if(ni) out.numId=attr(ni,'val');
    }
    return out;
  }

  parseRPr(rPr){
    const out={};
    if(!rPr) return out;
    if(directChild(rPr,'b')) out.bold = attr(directChild(rPr,'b'),'val') !== '0';
    if(directChild(rPr,'i')) out.italic = attr(directChild(rPr,'i'),'val') !== '0';
    if(directChild(rPr,'bCs')) out.bold = attr(directChild(rPr,'bCs'),'val') !== '0';
    if(directChild(rPr,'iCs')) out.italic = attr(directChild(rPr,'iCs'),'val') !== '0';
    const u=directChild(rPr,'u');
    if(u && attr(u,'val')!=='none') out.underline=true;
    const strike=directChild(rPr,'strike');
    if(strike) out.strike = attr(strike,'val') !== '0';
    const caps=directChild(rPr,'caps');
    if(caps) out.caps = attr(caps,'val') !== '0';
    const smallCaps=directChild(rPr,'smallCaps');
    if(smallCaps) out.smallCaps = attr(smallCaps,'val') !== '0';
    const color=directChild(rPr,'color');
    if(color) out.color=this.parseColor(color);
    const sz=directChild(rPr,'sz');
    if(sz) out.fontSizePt=halfPtToPt(attr(sz,'val'));
    const vert=directChild(rPr,'vertAlign');
    if(vert) out.vertAlign=attr(vert,'val');
    const shd=directChild(rPr,'shd');
    if(shd){
      const bg=this.parseShading(shd);
      if(bg) out.background=bg;
    }
    const hi=directChild(rPr,'highlight');
    if(hi){
      const hv=attr(hi,'val');
      const map={yellow:'#ffff00',green:'#00ff00',cyan:'#00ffff',magenta:'#ff00ff',blue:'#0000ff',red:'#ff0000',darkBlue:'#000080',darkCyan:'#008080',darkGreen:'#008000',darkMagenta:'#800080',darkRed:'#800000',darkYellow:'#808000',darkGray:'#808080',lightGray:'#c0c0c0',black:'#000000',white:'#ffffff'};
      if(map[hv]) out.background=map[hv];
    }
    return out;
  }

  mergedPProps(p){
    const pPr=directChild(p,'pPr');
    const pStyle=directChild(pPr,'pStyle');
    const styleId=pStyle ? attr(pStyle,'val') : null;
    const base=this.resolveStyle(styleId);
    return {styleId, props:{...base.p,...this.parsePPr(pPr)}, rBase:base.r};
  }

  cssFromPProps(props){
    const css={};
    const am={both:'justify',distribute:'justify',center:'center',right:'right',left:'left',start:'left',end:'right'};
    if(props.align) css.textAlign=am[props.align]||props.align;
    if(props.background) css.backgroundColor=props.background;
    if(props.borderTop) css.borderTop=props.borderTop;
    if(props.borderRight) css.borderRight=props.borderRight;
    if(props.borderBottom) css.borderBottom=props.borderBottom;
    if(props.borderLeft) css.borderLeft=props.borderLeft;
    if(props.indentRight) css.paddingRight=props.indentRight+'px';
    return css;
  }

  applyCss(el, css){
    for(const [k,v] of Object.entries(css||{})) if(v!=null) el.style[k]=v;
  }

  async render(){
    const root=document.createElement('div');
    root.className='doc-root';

    const body=first(this.document,'w\\:body, body');
    if(!body) throw new Error('document.xml has no body.');

    for(const child of Array.from(body.children)){
      if(child.localName==='p'){
        const node=await this.renderParagraph(child);
        if(node) root.appendChild(node);
      }else if(child.localName==='tbl'){
        const node=await this.renderTable(child);
        if(node){ root.appendChild(node); this.report.tables++; }
      }
    }
    this.applyCompactSpacing(root);
    this.applyFixedPalette(root);
    return root;
  }

  isEmptyParagraph(p){
    const text=qsa(p,'w\\:t, t').map(x=>x.textContent).join('').replace(/\u00a0/g,' ').trim();
    const hasDrawing=!!first(p,'w\\:drawing, drawing, w\\:pict, pict');
    const hasBreak=!!first(p,'w\\:br, br');
    return !text && !hasDrawing && !hasBreak;
  }

  getListInfo(p, merged){
    let numId=merged.props.numId, ilvl=merged.props.ilvl;
    if(numId==null && merged.styleId){
      const st=this.resolveStyle(merged.styleId);
      numId=st.p.numId; ilvl=st.p.ilvl;
    }
    if(numId==null) return null;
    ilvl=Number(ilvl||0);
    const absId=this.numberingMap.get(String(numId));
    const abs=this.abstractMap.get(String(absId));
    const lvl=abs?.levels.get(ilvl) || null;
    return {numId:String(numId),ilvl,lvl};
  }

  listMarker(info){
    const lvl=info.lvl;
    if(!lvl) return ['•','bullet'];
    if(lvl.numFmt==='bullet'){
      let t=(lvl.lvlText||'').trim();
      if(!t || /[\uF000-\uF8FF]/.test(t)) t=['•','○','▪'][Math.min(Math.max(Number(info.ilvl)||0,0),2)];
      return [t,'bullet'];
    }
    const key=info.numId+':'+info.ilvl;
    if(this.counters[key]==null) this.counters[key]=(lvl.start||1)-1;
    this.counters[key]++;
    let num=this.counters[key];
    let text=lvl.lvlText || `%${info.ilvl+1}.`;
    text=text.replace(/%(\d+)/g,(_,n)=> {
      const level=Number(n)-1;
      const k=info.numId+':'+level;
      const v=this.counters[k] ?? num;
      return this.formatNumber(v,lvl.numFmt);
    });
    return [text,'number'];
  }

  formatNumber(n, fmt){
    if(fmt==='lowerLetter') return String.fromCharCode(96+clamp(n,1,26));
    if(fmt==='upperLetter') return String.fromCharCode(64+clamp(n,1,26));
    if(fmt==='lowerRoman') return this.roman(n).toLowerCase();
    if(fmt==='upperRoman') return this.roman(n);
    return String(n);
  }

  roman(num){
    const map=[['M',1000],['CM',900],['D',500],['CD',400],['C',100],['XC',90],['L',50],['XL',40],['X',10],['IX',9],['V',5],['IV',4],['I',1]];
    let s=''; for(const [r,v] of map){while(num>=v){s+=r;num-=v}} return s;
  }

  async renderParagraph(p, insideTable=false){
    if(this.isEmptyParagraph(p)){ this.report.removedEmpty++; return null; }

    const merged=this.mergedPProps(p);
    const semantic=this.semanticStyleForParagraph(p,merged);
    const el=document.createElement('div');
    el.className='doc-p';
    if(semantic.kind==='heading'){
      el.classList.add('h'+semantic.level);
      this.report['h'+semantic.level]++;
      el.dataset.headingLevel=semantic.level;
      if(semantic.flattened) el.dataset.flattenedSemantic='true';
    }else if(semantic.kind==='boldside'){
      el.classList.add('boldside'+semantic.level);
      this.report['bs'+semantic.level]++;
      if(semantic.flattened) el.dataset.flattenedSemantic='true';
    }
    el.dataset.styleId=merged.styleId||'';
    el.dataset.styleName=this.styleMap.get(merged.styleId)?.name||'';

    this.applyCss(el,this.cssFromPProps(merged.props));

    if(semantic.kind==='heading' && semantic.level===1){
      const h1R={...merged.rBase};
      const firstRun=first(p,'w\\:r, r');
      if(firstRun) Object.assign(h1R,this.parseRPr(directChild(firstRun,'rPr')));
      if(h1R.fontSizePt) el.style.fontSize=h1R.fontSizePt+'pt';
      if(h1R.color) el.style.color=h1R.color;
      if(h1R.bold!=null) el.style.fontWeight=h1R.bold?'700':'400';
    }else if(semantic.kind==='heading' || semantic.kind==='boldside'){
      if(merged.rBase.color) el.style.color=merged.rBase.color;
    }

    const list=this.getListInfo(p,merged);
    if(list){
      this.report.lists++;
      el.classList.add('doc-list');
      const [marker,markerType]=this.listMarker(list);
      const mk=document.createElement('span');
      mk.className='list-marker '+(markerType==='bullet' ? 'is-bullet' : 'is-number');
      mk.textContent=markerType==='bullet' ? '' : marker;

      const content=document.createElement('span');
      content.className='list-content';
      await this.renderParagraphInlineContent(p,content,merged.rBase,{
        isHeading: semantic.kind==='heading' || semantic.kind==='boldside',
        insideTable
      });

      /*
       * Word list geometry:
       *   w:ind/@left    = text start
       *   w:ind/@hanging = distance back from text start to marker area
       *
       * The numbering level's indentation must not be accidentally replaced by
       * a paragraph-style indent inherited through merged.props. Direct paragraph
       * formatting wins; otherwise the numbering-level geometry wins; the paragraph
       * style is only a final fallback.
       */
      const directPPr = this.parsePPr(directChild(p,'pPr'));
      const levelPPr = list.lvl ? this.parsePPr(list.lvl.pPr) : {};

      const rawLeft = directPPr.indentLeft != null
        ? directPPr.indentLeft
        : (levelPPr.indentLeft != null ? levelPPr.indentLeft : (merged.props.indentLeft || 0));

      const rawHanging = directPPr.hanging != null
        ? directPPr.hanging
        : (levelPPr.hanging != null ? levelPPr.hanging : (merged.props.hanging || 0));

      /*
       * Fixed three-level list geometry.
       *
       * One visual step is exactly 26 px:
       *   18 px marker box + 8 px marker-to-text gap.
       *
       * Therefore:
       *   Level 2 MARKER starts exactly at Level 1 TEXT start.
       *   Level 3 MARKER starts exactly at Level 2 TEXT start.
       *
       * Word determines only the Level-1 text anchor. The visual nesting itself is
       * deliberately fixed so paragraph/list overrides cannot collapse the hierarchy.
       */
      const absId = this.numberingMap.get(String(list.numId));
      const abs = this.abstractMap.get(String(absId));
      const level0 = abs?.levels.get(0);
      const level0Pr = level0 ? this.parsePPr(level0.pPr) : {};

      const level1TextStart = level0Pr.indentLeft != null
        ? level0Pr.indentLeft
        : (list.ilvl === 0 && rawLeft > 0 ? rawLeft : 36);

      // Normalize the THREE visual bullet levels from the actual Word bullet glyph.
      // This is necessary because Word may restart/switch numbering definitions and
      // store a visually nested hollow-circle/square paragraph as ilvl=0.
      // For bullets, the Word glyph is therefore the stable visual source of truth:
      //   • = Level 1, ○ = Level 2, ▪ = Level 3.
      // Numbered lists continue to use ilvl.
      const normalizedMarker = String(marker || '').trim();
      let visualLevel;
      if (markerType === 'bullet') {
        if (normalizedMarker === '○' || normalizedMarker === 'o' || normalizedMarker === '◦') {
          visualLevel = 1;
        } else if (normalizedMarker === '▪' || normalizedMarker === '■' || normalizedMarker === '▫' || normalizedMarker === '□') {
          visualLevel = 2;
        } else {
          visualLevel = 0;
        }
      } else {
        visualLevel = Math.min(Math.max(Number(list.ilvl) || 0, 0), 2);
      }

      /*
       * FINAL THREE-LEVEL BULLET GEOMETRY
       *
       * Bullet positioning is intentionally independent of Word w:ind / numId.
       * Word list definitions may restart or switch numId and otherwise collapse
       * visually nested bullets. Only the visual level is retained.
       *
       * Fixed geometry from the document content edge:
       *
       *   L1 marker:  0 px      L1 text: 20 px
       *   L2 marker: 20 px      L2 text: 40 px
       *   L3 marker: 40 px      L3 text: 60 px
       *
       * Thus L2 marker == L1 text start, and L3 marker == L2 text start.
       * One complete nesting step is exactly 20 px.
       */
      const markerBox = 12;
      const markerGap = 8;
      const levelStep = markerBox + markerGap; // exactly 20 px

      const markerStart = visualLevel * levelStep;
      const left = markerStart + levelStep;

      el.style.setProperty('--list-indent', markerStart+'px');
      el.style.setProperty('--marker-col', markerBox+'px');
      el.style.setProperty('--marker-gap', markerGap+'px');

      el.dataset.listLevel=String(visualLevel);
      el.dataset.wordIlvl=String(list.ilvl);
      el.dataset.wordBulletGlyph=String(marker || '');
      el.dataset.wordRawTextStart=String(Math.round(rawLeft));
      el.dataset.effectiveTextStart=String(Math.round(left));
      el.dataset.wordHanging=String(Math.round(rawHanging));
      el.append(mk,content);
    }else{
      const left=merged.props.indentLeft||0;
      const firstLine=merged.props.firstLine||0;
      if(left) el.style.paddingLeft=left+'px';
      if(firstLine) el.style.textIndent=firstLine+'px';
      await this.renderParagraphInlineContent(p,el,merged.rBase,{
        isHeading: semantic.kind==='heading' || semantic.kind==='boldside',
        insideTable
      });
    }

    if(semantic.kind==='heading'){
      const txt=el.textContent.trim();
      el.dataset.headingText=txt;
      el.id='word-heading-'+crypto.randomUUID();
    }

    // Spacing lives on a transparent outer block so Word shading/background
    // paints only the paragraph itself, never the space-before/space-after area.
    const block=document.createElement('div');
    block.className='doc-block';
    if(semantic.kind==='heading') block.classList.add('h'+semantic.level);
    else if(semantic.kind==='boldside') block.classList.add('boldside'+semantic.level);
    block.appendChild(el);
    return block;
  }

  async renderParagraphInlineContent(p,target,baseR,context={}){
    for(const node of Array.from(p.children)){
      if(node.localName==='r'){
        await this.renderRun(node,target,baseR,context);
      }else if(node.localName==='hyperlink'){
        const a=document.createElement('span');
        for(const r of directChildren(node,'r')) await this.renderRun(r,a,baseR,context);
        target.appendChild(a);
      }else if(node.localName==='fldSimple'){
        for(const r of directChildren(node,'r')) await this.renderRun(r,target,baseR,context);
      }
    }
  }

  async renderRun(r,target,baseR,context={}){
    /*
     * Resolve Word CHARACTER styles (w:rStyle) before applying direct run
     * formatting. This preserves styles such as Emphasis, Subtle Emphasis,
     * Strong, Intense Emphasis, etc. from styles.xml.
     *
     * Precedence follows Word's cascade:
     *   paragraph run defaults -> character style -> direct run formatting
     */
    const runPr=directChild(r,'rPr');
    const rStyleNode=directChild(runPr,'rStyle');
    const rStyleId=rStyleNode ? attr(rStyleNode,'val') : null;
    const charStyleR = rStyleId ? this.resolveStyle(rStyleId).r : {};
    const directR = this.parseRPr(runPr);

    // First resolve the run normally so we know whether it is actually bold.
    let rProps={
      ...baseR,
      ...charStyleR,
      ...directR
    };

    /*
     * Body-bold normalization:
     * Outside headings/BoldSide paragraphs and outside tables, every bold run
     * that is NOT already using an Emphasis-family character style inherits
     * Word's Subtle Emphasis character style.
     *
     * Direct formatting still wins over Subtle Emphasis, so existing explicit
     * color/italic/underline choices are never destroyed.
     */
    const currentStyleName = this.styleMap.get(rStyleId)?.name || rStyleId || '';
    const currentStyleNorm = normalizeStyle(currentStyleName);
    const alreadyEmphasis = currentStyleNorm.includes('emphasis');

    if(rProps.bold && !context.isHeading && !context.insideTable && !alreadyEmphasis){
      let subtleStyleId = null;
      for(const [sid,st] of this.styleMap.entries()){
        if(st.type==='character' && normalizeStyle(st.name || sid)==='subtleemphasis'){
          subtleStyleId = sid;
          break;
        }
      }

      if(subtleStyleId){
        const subtleR = this.resolveStyle(subtleStyleId).r;
        rProps = {
          ...baseR,
          ...charStyleR,
          ...subtleR,
          ...directR
        };
      }
    }

    const drawings=directChildren(r,'drawing');
    const picts=directChildren(r,'pict');
    const textNodes=Array.from(r.children).filter(n=>['t','tab','br','cr','noBreakHyphen','softHyphen'].includes(n.localName));

    for(const n of textNodes){
      if(n.localName==='br' || n.localName==='cr'){ target.appendChild(document.createElement('br')); continue; }
      const span=document.createElement('span');
      let text='';
      if(n.localName==='tab') text='\t';
      else if(n.localName==='noBreakHyphen') text='‑';
      else if(n.localName==='softHyphen') text='­';
      else text=n.textContent || '';
      span.textContent=text;
      if(rStyleId) span.dataset.wordCharacterStyle=rStyleId;
      if(rProps.bold && !context.isHeading && !context.insideTable){
        const styleName = this.styleMap.get(rStyleId)?.name || rStyleId || '';
        if(!normalizeStyle(styleName).includes('emphasis')){
          span.dataset.autoSubtleEmphasis='true';
        }
      }
      if(rProps.bold) span.style.fontWeight='700';
      /* Italics intentionally disabled in main notes formatting. */
      if(rProps.underline) span.style.textDecoration=(span.style.textDecoration?span.style.textDecoration+' ':'')+'underline';
      if(rProps.strike) span.style.textDecoration=(span.style.textDecoration?span.style.textDecoration+' ':'')+'line-through';
      if(rProps.caps) span.style.textTransform='uppercase';
      if(rProps.smallCaps) span.style.fontVariantCaps='small-caps';
      if(rProps.color) span.style.color=rProps.color;
      if(rProps.fontSizePt) span.style.fontSize=rProps.fontSizePt+'pt';
      if(rProps.background) span.style.backgroundColor=rProps.background;
      if(rProps.vertAlign==='superscript'){span.style.verticalAlign='super';span.style.fontSize='0.75em'}
      if(rProps.vertAlign==='subscript'){span.style.verticalAlign='sub';span.style.fontSize='0.75em'}
      target.appendChild(span);
    }

    for(const d of drawings){
      const img=await this.renderDrawing(d);
      if(img) target.appendChild(img);
    }
    // Legacy VML images: size support is intentionally limited, but do not drop the image.
    for(const p of picts){
      const im=first(p,'v\\:imagedata, imagedata');
      if(im){
        const rid=im.getAttributeNS(NS.r,'id') || im.getAttribute('r:id');
        const node=await this.imageFromRid(rid,null,null,null);
        if(node) target.appendChild(node);
      }
    }
  }

  async renderDrawing(drawing){
    const blip=first(drawing,'a\\:blip, blip');
    if(!blip) return null;
    const rid=blip.getAttributeNS(NS.r,'embed') || blip.getAttribute('r:embed');
    if(!rid) return null;

    const extent=first(drawing,'wp\\:extent, extent');
    let w=extent ? emuToPx(extent.getAttribute('cx')) : null;
    let h=extent ? emuToPx(extent.getAttribute('cy')) : null;

    const srcRect=first(drawing,'a\\:srcRect, srcRect');
    let crop=null;
    if(srcRect){
      crop={
        l:Number(srcRect.getAttribute('l')||0)/100000,
        t:Number(srcRect.getAttribute('t')||0)/100000,
        r:Number(srcRect.getAttribute('r')||0)/100000,
        b:Number(srcRect.getAttribute('b')||0)/100000
      };
    }
    return await this.imageFromRid(rid,w,h,crop);
  }

  async imageFromRid(rid,w,h,crop){
    const target=this.relMap.get(rid);
    if(!target) return null;
    const clean='word/'+target.replace(/^\.\//,'').replace(/^\//,'');
    const file=this.zip.file(clean);
    if(!file) return null;
    const blob=await file.async('blob');

    // Remove Word-exported divider strip images.
    if(h!=null && h<=3.5){
      this.report.removedStrips++;
      return null;
    }

    this.report.images++;
    let url;
    if(crop && (crop.l||crop.t||crop.r||crop.b)){
      try{
        url=await this.cropRaster(blob,crop);
      }catch(e){
        console.warn('Crop failed; using original image',e);
        url=URL.createObjectURL(blob); objectUrls.push(url);
      }
    }else{
      url=URL.createObjectURL(blob); objectUrls.push(url);
    }

    const wrap=document.createElement('span');
    wrap.className='doc-image-wrap';
    wrap.style.display='inline-block';
    wrap.style.verticalAlign='middle';

    const img=document.createElement('img');
    img.src=url; img.alt='';
    if(w!=null) img.style.width=w+'px';
    if(h!=null) img.style.height=h+'px';
    wrap.appendChild(img);
    return wrap;
  }

  async cropRaster(blob,crop){
    const bmp=await createImageBitmap(blob);
    const sx=Math.round(bmp.width*crop.l);
    const sy=Math.round(bmp.height*crop.t);
    const sw=Math.max(1,Math.round(bmp.width*(1-crop.l-crop.r)));
    const sh=Math.max(1,Math.round(bmp.height*(1-crop.t-crop.b)));
    const canvas=document.createElement('canvas');
    canvas.width=sw;canvas.height=sh;
    const ctx=canvas.getContext('2d');
    ctx.drawImage(bmp,sx,sy,sw,sh,0,0,sw,sh);
    bmp.close();
    const out=await new Promise(res=>canvas.toBlob(res,'image/webp',0.90));
    const url=URL.createObjectURL(out || blob); objectUrls.push(url); return url;
  }

  tableStyleLayers(styleId, seen=new Set()){
    if(!styleId || seen.has(styleId)) return [];
    const st=this.styleMap.get(styleId);
    if(!st || st.type!=='table') return [];
    seen.add(styleId);
    const layers=st.basedOn ? this.tableStyleLayers(st.basedOn,seen) : [];
    layers.push(st.raw);
    return layers;
  }

  tableBorderMap(tblBorders){
    const out={};
    if(!tblBorders) return out;
    for(const side of ['top','right','bottom','left','insideH','insideV']){
      const node=directChild(tblBorders,side);
      if(!node) continue;
      const val=attr(node,'val');
      out[side]=(val==='nil'||val==='none') ? '' : this.parseBorderSide(node);
    }
    return out;
  }

  parseCellMargins(tblPr){
    const mar=directChild(tblPr,'tblCellMar');
    const out={};
    if(!mar) return out;
    for(const side of ['top','right','bottom','left']){
      const n=directChild(mar,side);
      if(n && attr(n,'w')!=null) out[side]=twipToPx(attr(n,'w'));
    }
    return out;
  }

  mergeTablePr(out, tblPr){
    if(!tblPr) return out;
    const shd=directChild(tblPr,'shd');
    const bg=this.parseShading(shd);
    if(bg) out.background=bg;
    Object.assign(out.borders, this.tableBorderMap(directChild(tblPr,'tblBorders')));
    Object.assign(out.cellMargins, this.parseCellMargins(tblPr));
    return out;
  }

  mergeTcPr(out, tcPr){
    if(!tcPr) return out;
    const bg=this.parseShading(directChild(tcPr,'shd'));
    if(bg) out.background=bg;
    Object.assign(out.borders, this.tableBorderMap(directChild(tcPr,'tcBorders')));
    const v=directChild(tcPr,'vAlign');
    if(v) out.vAlign=attr(v,'val');
    return out;
  }

  tableLookFlags(tblPr){
    const look=directChild(tblPr,'tblLook');
    const yes=(name,def=false)=>{
      if(!look) return def;
      const v=attr(look,name);
      return v==null ? def : (v==='1'||v==='true'||v==='on');
    };
    return {
      firstRow:yes('firstRow',true), lastRow:yes('lastRow',false),
      firstColumn:yes('firstColumn',false), lastColumn:yes('lastColumn',false),
      noHBand:yes('noHBand',false), noVBand:yes('noVBand',true)
    };
  }

  collectTableStyle(styleId, tblPr){
    const result={base:{borders:{},cellMargins:{}}, cond:new Map()};
    for(const raw of this.tableStyleLayers(styleId)){
      this.mergeTablePr(result.base,directChild(raw,'tblPr'));
      const baseTc=directChild(raw,'tcPr');
      result.base.tc=result.base.tc||{borders:{}};
      this.mergeTcPr(result.base.tc,baseTc);
      result.base.r={...(result.base.r||{}),...this.parseRPr(directChild(raw,'rPr'))};
      result.base.p={...(result.base.p||{}),...this.parsePPr(directChild(raw,'pPr'))};
      for(const c of directChildren(raw,'tblStylePr')){
        const type=attr(c,'type');
        if(!type) continue;
        const x=result.cond.get(type)||{tbl:{borders:{},cellMargins:{}},tc:{borders:{}},r:{},p:{}};
        this.mergeTablePr(x.tbl,directChild(c,'tblPr'));
        this.mergeTcPr(x.tc,directChild(c,'tcPr'));
        Object.assign(x.r,this.parseRPr(directChild(c,'rPr')));
        Object.assign(x.p,this.parsePPr(directChild(c,'pPr')));
        result.cond.set(type,x);
      }
    }
    this.mergeTablePr(result.base,tblPr); // direct table formatting wins over style base
    return result;
  }

  tableConditionTypes(r,c,rowCount,colCount,look){
    const a=['wholeTable'];
    if(look.firstRow && r===0) a.push('firstRow');
    if(look.lastRow && r===rowCount-1) a.push('lastRow');
    if(look.firstColumn && c===0) a.push('firstCol');
    if(look.lastColumn && c===colCount-1) a.push('lastCol');
    if(!look.noHBand) a.push(r%2===0?'band1Horz':'band2Horz');
    if(!look.noVBand) a.push(c%2===0?'band1Vert':'band2Vert');
    if(r===0 && c===0) a.push('nwCell');
    if(r===0 && c===colCount-1) a.push('neCell');
    if(r===rowCount-1 && c===0) a.push('swCell');
    if(r===rowCount-1 && c===colCount-1) a.push('seCell');
    return a;
  }

  applyTableBorders(cell,borders,r,c,rowCount,colCount){
    const set=(side,val)=>{ if(val!==undefined) cell.style['border'+side]=val||'none'; };
    set('Top', r===0 ? borders.top : borders.insideH);
    set('Bottom', r===rowCount-1 ? borders.bottom : borders.insideH);
    set('Left', c===0 ? borders.left : borders.insideV);
    set('Right', c===colCount-1 ? borders.right : borders.insideV);
  }

  async renderTable(tbl){
    const table=document.createElement('table');
    const tblPr=directChild(tbl,'tblPr');
    const tblStyleNode=directChild(tblPr,'tblStyle');
    const tblStyleId=tblStyleNode ? attr(tblStyleNode,'val') : null;
    const style=this.collectTableStyle(tblStyleId,tblPr);
    const look=this.tableLookFlags(tblPr);

    table.dataset.wordTableStyle=tblStyleId||'';
    table.style.marginLeft='auto'; table.style.marginRight='auto';
    if(style.base.background) table.style.backgroundColor=style.base.background;

    const tblW=directChild(tblPr,'tblW');
    if(tblW && attr(tblW,'type')==='dxa') table.style.width=twipToPx(attr(tblW,'w'))+'px';

    const grid=directChild(tbl,'tblGrid');
    if(grid){
      const cols=directChildren(grid,'gridCol');
      if(cols.length){
        const cg=document.createElement('colgroup');
        cols.forEach(c=>{
          const col=document.createElement('col');
          const ww=attr(c,'w');
          if(ww) col.style.width=twipToPx(ww)+'px';
          cg.appendChild(col);
        });
        table.appendChild(cg);
      }
    }

    const rows=directChildren(tbl,'tr');
    const rowCount=rows.length;
    const colCount=Math.max(1,...rows.map(tr=>directChildren(tr,'tc').reduce((n,tc)=>{
      const span=directChild(directChild(tc,'tcPr'),'gridSpan');
      return n+Number(span?attr(span,'val'):1);
    },0)));

    for(let ri=0;ri<rows.length;ri++){
      const tr=rows[ri];
      const row=document.createElement('tr');
      let logicalCol=0;
      for(const tc of directChildren(tr,'tc')){
        const cell=document.createElement('td');
        const tcPr=directChild(tc,'tcPr');
        const spanNode=directChild(tcPr,'gridSpan');
        const colspan=Number(spanNode?attr(spanNode,'val'):1);
        if(colspan>1) cell.colSpan=colspan;

        const effective={
          background:style.base.tc?.background || style.base.background || null,
          borders:{...style.base.borders,...(style.base.tc?.borders||{})},
          r:{...(style.base.r||{})}, p:{...(style.base.p||{})},
          cellMargins:{...style.base.cellMargins}, vAlign:style.base.tc?.vAlign||null
        };
        const conds=this.tableConditionTypes(ri,logicalCol,rowCount,colCount,look);
        for(const type of conds){
          const x=style.cond.get(type); if(!x) continue;
          if(x.tbl.background) effective.background=x.tbl.background;
          Object.assign(effective.borders,x.tbl.borders||{});
          Object.assign(effective.cellMargins,x.tbl.cellMargins||{});
          if(x.tc.background) effective.background=x.tc.background;
          Object.assign(effective.borders,x.tc.borders||{});
          if(x.tc.vAlign) effective.vAlign=x.tc.vAlign;
          Object.assign(effective.r,x.r||{}); Object.assign(effective.p,x.p||{});
        }
        const direct={borders:{}};
        this.mergeTcPr(direct,tcPr);
        if(direct.background) effective.background=direct.background;
        Object.assign(effective.borders,direct.borders||{});
        if(direct.vAlign) effective.vAlign=direct.vAlign;

        if(effective.background) cell.style.backgroundColor=effective.background;
        if(effective.vAlign) cell.style.verticalAlign=effective.vAlign==='center'?'middle':effective.vAlign;
        this.applyTableBorders(cell,effective.borders,ri,logicalCol,rowCount,colCount);
        const m=effective.cellMargins;
        if(m.top!=null) cell.style.paddingTop=m.top+'px';
        if(m.right!=null) cell.style.paddingRight=m.right+'px';
        if(m.bottom!=null) cell.style.paddingBottom=m.bottom+'px';
        if(m.left!=null) cell.style.paddingLeft=m.left+'px';

        const tcW=directChild(tcPr,'tcW');
        if(tcW && attr(tcW,'type')==='dxa') cell.style.width=twipToPx(attr(tcW,'w'))+'px';

        if(effective.r.color) cell.style.color=effective.r.color;
        if(effective.r.bold) cell.style.fontWeight='700';
        /* Italics intentionally disabled in table formatting. */

        for(const c of Array.from(tc.children)){
          if(c.localName==='p'){
            const p=await this.renderParagraph(c,true);
            if(p){
              // Table-style paragraph/run formatting is inherited unless the paragraph/run has an explicit Word override.
              if(effective.p.align && !p.style.textAlign){
                const am={both:'justify',distribute:'justify',center:'center',right:'right',left:'left',start:'left',end:'right'};
                p.style.textAlign=am[effective.p.align]||effective.p.align;
              }
              p.style.fontSize='9.5pt';
              cell.appendChild(p);
            }
          }else if(c.localName==='tbl'){
            const nested=await this.renderTable(c);
            if(nested) cell.appendChild(nested);
          }
        }
        row.appendChild(cell);
        logicalCol+=colspan;
      }
      table.appendChild(row);
    }
    return table;
  }

  applyFixedPalette(root){
    const P={
      burgundy:'#6F3D5D',
      white:'#FFFFFF',
      lavender:'#E7E1E4',
      black:'#000000',
      navy:'#294C7B'
    };

    for(const el of root.querySelectorAll('*')){
      if(el.tagName==='IMG') continue;

      const p=el.closest('.doc-p');
      const table=el.closest('table');

      if(table){
        if(el.style.borderTopColor) el.style.borderTopColor=P.navy;
        if(el.style.borderRightColor) el.style.borderRightColor=P.navy;
        if(el.style.borderBottomColor) el.style.borderBottomColor=P.navy;
        if(el.style.borderLeftColor) el.style.borderLeftColor=P.navy;
        continue;
      }

      if(p?.classList.contains('h1')){
        el.style.color=P.white;
        if(el!==p) el.style.backgroundColor='transparent';
      }else if(p?.classList.contains('h2')){
        el.style.color='#5C3A52';
        if(el!==p && el.style.backgroundColor) el.style.backgroundColor='transparent';
      }else if(p?.classList.contains('h3')){
        el.style.color='#294C7B';
        if(el!==p && el.style.backgroundColor) el.style.backgroundColor='transparent';
      }else if(p?.classList.contains('h4')){
        el.style.color='#5C3A52';
        if(el!==p && el.style.backgroundColor) el.style.backgroundColor='transparent';
      }else if(p?.classList.contains('boldside1')){
        el.style.color=P.burgundy;
        if(el.style.backgroundColor) el.style.backgroundColor='transparent';
      }else if(p?.classList.contains('boldside2') || p?.classList.contains('boldside3')){
        el.style.color=P.navy;
        if(el.style.backgroundColor) el.style.backgroundColor='transparent';
      }else{
        const charStyle=normalizeStyle(el.dataset?.wordCharacterStyle || '');
        if(charStyle==='emphasis'){
          el.style.color='#6F3D5D';
        }else if(charStyle==='subtleemphasis' || el.dataset?.autoSubtleEmphasis==='true'){
          el.style.color='#28467C';
        }else{
          el.style.color=P.black;
        }

        // Remove imported run-level shading/highlight blocks.
        // Keep semantic text styling (color, bold, italic) only.
        if(el!==p){
          el.style.setProperty('background','transparent','important');
          el.style.setProperty('background-color','transparent','important');
        }
      }

      if(el.style.borderTopColor) el.style.borderTopColor=P.navy;
      if(el.style.borderRightColor) el.style.borderRightColor=P.navy;
      if(el.style.borderBottomColor) el.style.borderBottomColor=P.navy;
      if(el.style.borderLeftColor) el.style.borderLeftColor=P.navy;
      if(el.style.textDecorationColor) el.style.textDecorationColor='currentColor';
    }

    for(const p of root.querySelectorAll('.doc-p.h1')){
      p.style.backgroundColor=P.burgundy;
      p.style.color=P.white;
      p.style.borderColor=P.burgundy;
    }

    for(const table of root.querySelectorAll('table')){
      table.style.setProperty('border-collapse','collapse','important');
      table.style.setProperty('border-spacing','0','important');
      table.style.setProperty('background-color',P.white,'important');
      table.style.setProperty('border-color',P.navy,'important');

      const rows=Array.from(table.rows);

      rows.forEach((row,rowIndex)=>{
        row.classList.remove('cnl-table-header','cnl-table-white','cnl-table-lavender');

        if(rowIndex===0){
          row.classList.add('cnl-table-header');
        }else{
          // First body row white, second lavender, then alternate.
          row.classList.add(((rowIndex-1)%2===0) ? 'cnl-table-white' : 'cnl-table-lavender');
        }

        for(const cell of Array.from(row.cells)){
          const isHeader=rowIndex===0;
          const fill=isHeader
            ? P.burgundy
            : (((rowIndex-1)%2===0) ? P.white : P.lavender);
          const text=isHeader ? P.white : P.black;

          // Force the ENTIRE CELL fill, not the paragraph/run fill.
          cell.style.setProperty('background',fill,'important');
          cell.style.setProperty('background-color',fill,'important');
          cell.style.setProperty('color',text,'important');
          cell.style.setProperty('border-color',P.navy,'important');

          // Remove all imported Word shading from descendants.
          for(const d of cell.querySelectorAll('*')){
            if(d.tagName==='IMG') continue;

            d.style.setProperty('background','transparent','important');
            d.style.setProperty('background-color','transparent','important');
            d.style.setProperty('color',text,'important');

            if(d.style.borderTopColor) d.style.setProperty('border-top-color',P.navy,'important');
            if(d.style.borderRightColor) d.style.setProperty('border-right-color',P.navy,'important');
            if(d.style.borderBottomColor) d.style.setProperty('border-bottom-color',P.navy,'important');
            if(d.style.borderLeftColor) d.style.setProperty('border-left-color',P.navy,'important');
          }
        }
      });
    }
  }

  applyCompactSpacing(root){
    const meaningful=Array.from(root.children).filter(el=>el.matches('.doc-block,table'));
    const isHeading = el => el?.classList && ['h1','h2','h3','h4'].some(c=>el.classList.contains(c));
    const hLevel = el => {
      for(let i=1;i<=4;i++) if(el?.classList?.contains('h'+i)) return i;
      return 0;
    };
    const bsLevel = el => {
      for(let i=1;i<=3;i++) if(el?.classList?.contains('boldside'+i)) return i;
      return 0;
    };

    for(let i=1;i<meaningful.length;i++){
      const prev=meaningful[i-1], cur=meaningful[i];
      if(!cur.classList?.contains('doc-block')) continue;

      const ph=hLevel(prev), ch=hLevel(cur), pb=bsLevel(prev), cb=bsLevel(cur);
      let compact=false;

      if(ph && ch && ch===ph+1) compact=true;                // H1→H2, H2→H3, H3→H4

      /*
       * Keep normal visible spacing for:
       *   H2 → BoldSide1
       *   BoldSide1 → BoldSide2
       *   BoldSide1 → BoldSide3
       *
       * These transitions intentionally do NOT receive compact-before,
       * so their normal --bs1-before / --bs2-before / --bs3-before
       * spacing remains intact.
       */

      if(compact) cur.classList.add('compact-before');
    }
  }
}

/**
 * Word stores equations as OMML (m:oMath / m:oMathPara / m:t). The page's
 * DocxPrototype only walked w:r / w:t, so a math-only paragraph looked empty
 * and was dropped, and mixed text+formula lines lost the formula. Flatten
 * OMML to readable text in document order, and decode leftover LaTeX in runs.
 */
(function () {
  if (typeof DocxPrototype === 'undefined' || !DocxPrototype.prototype) return;
  var proto = DocxPrototype.prototype;
  var MATH_NS = 'http://schemas.openxmlformats.org/officeDocument/2006/math';

  function localName(node) {
    return String((node && node.localName) || '').replace(/^.*:/, '');
  }

  function mathAttr(el, name) {
    if (!el || !el.getAttribute) return '';
    return el.getAttributeNS(MATH_NS, name) ||
      el.getAttribute('m:' + name) ||
      el.getAttribute(name) || '';
  }

  function firstChild(node, tag) {
    var kids = node && node.children ? node.children : [];
    for (var i = 0; i < kids.length; i++) {
      if (localName(kids[i]) === tag) return kids[i];
    }
    return null;
  }

  function skipPr(name) {
    return /Pr$/.test(name) || name === 'ctrlPr';
  }

  function wrapScript(s, mark) {
    s = String(s || '').trim();
    if (!s) return '';
    return mark + (s.length === 1 ? s : '(' + s + ')');
  }

  function ommlText(node) {
    if (!node) return '';
    if (node.nodeType === 3) return node.nodeValue || '';
    var name = localName(node);
    if (name === 't') return node.textContent || '';
    if (skipPr(name)) return '';
    if (name === 'f') {
      return '(' + ommlText(firstChild(node, 'num')).trim() + ') / (' +
        ommlText(firstChild(node, 'den')).trim() + ')';
    }
    if (name === 'sSup') {
      return ommlText(firstChild(node, 'e')) + wrapScript(ommlText(firstChild(node, 'sup')), '^');
    }
    if (name === 'sSub') {
      return ommlText(firstChild(node, 'e')) + wrapScript(ommlText(firstChild(node, 'sub')), '_');
    }
    if (name === 'sSubSup') {
      return ommlText(firstChild(node, 'e')) +
        wrapScript(ommlText(firstChild(node, 'sub')), '_') +
        wrapScript(ommlText(firstChild(node, 'sup')), '^');
    }
    if (name === 'rad') {
      var deg = ommlText(firstChild(node, 'deg')).trim();
      return (deg ? deg : '') + '√(' + ommlText(firstChild(node, 'e')).trim() + ')';
    }
    if (name === 'd') {
      return '(' + ommlText(firstChild(node, 'e')) + ')';
    }
    if (name === 'nary') {
      var chr = mathAttr(firstChild(firstChild(node, 'naryPr'), 'chr'), 'val') || '∑';
      return chr +
        wrapScript(ommlText(firstChild(node, 'sub')), '_') +
        wrapScript(ommlText(firstChild(node, 'sup')), '^') +
        ommlText(firstChild(node, 'e'));
    }
    var kids = node.children ? Array.from(node.children) : [];
    return kids.map(ommlText).join('');
  }

  function flattenQuotedFrac(text) {
    return String(text || '')
      .replace(/[\u201C\u201D]/g, '"')
      .replace(/"([^"]+)"\s*\/\s*"([^"]+)"/g, '($1) / ($2)');
  }

  function readable(text) {
    text = flattenQuotedFrac(String(text || '').replace(/\s+/g, ' ').trim());
    if (!text) return '';
    var clean = typeof window.cnlCleanPasteText === 'function' ? window.cnlCleanPasteText : null;
    if (clean && (/\\[a-zA-Z]/.test(text) || /\$/.test(text))) {
      try { text = clean(text) || text; } catch (ignore) {}
    }
    return text;
  }

  function appendFormula(node, target) {
    var text = readable(ommlText(node));
    if (!text || !target) return;
    var span = document.createElement('span');
    span.className = 'doc-formula';
    // Parse _ and ^ markers into actual sub/sup elements
    var i = 0;
    while (i < text.length) {
      var c = text[i];
      if (c === '_' || c === '^') {
        i++;
        if (i >= text.length) break;
        var script = '';
        if (text[i] === '(') {
          // Multi-character script: find closing paren
          i++;
          var depth = 1;
          while (i < text.length && depth > 0) {
            if (text[i] === '(') depth++;
            else if (text[i] === ')') depth--;
            if (depth > 0) script += text[i];
            i++;
          }
        } else {
          // Single character script
          script = text[i];
          i++;
        }
        var el = document.createElement(c === '_' ? 'sub' : 'sup');
        el.textContent = script;
        span.appendChild(el);
      } else {
        // Regular text - accumulate and append as text node
        var regular = '';
        while (i < text.length && text[i] !== '_' && text[i] !== '^') {
          regular += text[i];
          i++;
        }
        if (regular) span.appendChild(document.createTextNode(regular));
      }
    }
    target.appendChild(span);
  }

  function hasMath(p) {
    if (!p) return false;
    if (p.getElementsByTagNameNS) {
      if (p.getElementsByTagNameNS(MATH_NS, 'oMath').length) return true;
      if (p.getElementsByTagNameNS(MATH_NS, 'oMathPara').length) return true;
      var ts = p.getElementsByTagNameNS(MATH_NS, 't');
      for (var i = 0; i < ts.length; i++) {
        if (String(ts[i].textContent || '').replace(/\u00a0/g, ' ').trim()) return true;
      }
    }
    var all = p.getElementsByTagName ? p.getElementsByTagName('*') : [];
    for (var j = 0; j < all.length; j++) {
      var n = localName(all[j]);
      if (n === 'oMath' || n === 'oMathPara') return true;
    }
    return false;
  }

  var origEmpty = proto.isEmptyParagraph;
  proto.isEmptyParagraph = function (p) {
    if (hasMath(p)) return false;
    return origEmpty.call(this, p);
  };

  proto.renderParagraphInlineContent = async function (p, target, baseR, context) {
    var self = this;
    async function walk(parent, dest) {
      var nodes = Array.from((parent && parent.children) || []);
      for (var i = 0; i < nodes.length; i++) {
        var node = nodes[i];
        var name = localName(node);
        if (name === 'r') {
          await self.renderRun(node, dest, baseR, context);
        } else if (name === 'hyperlink') {
          var a = document.createElement('span');
          var runs = typeof directChildren === 'function' ? directChildren(node, 'r') : [];
          if (runs.length) {
            for (var r = 0; r < runs.length; r++) await self.renderRun(runs[r], a, baseR, context);
          } else {
            await walk(node, a);
          }
          dest.appendChild(a);
        } else if (name === 'fldSimple') {
          await walk(node, dest);
        } else if (name === 'oMath' || name === 'oMathPara') {
          appendFormula(node, dest);
        } else if (name === 'sdt') {
          await walk(firstChild(node, 'sdtContent') || node, dest);
        } else if (name === 'ins' || name === 'smartTag' || name === 'customXml') {
          await walk(node, dest);
        } else if (name === 'AlternateContent') {
          await walk(firstChild(node, 'Choice') || firstChild(node, 'Fallback') || node, dest);
        }
      }
    }
    await walk(p, target);
  };

  var origRun = proto.renderRun;
  proto.renderRun = async function (r, target, baseR, context) {
    var start = target ? target.childNodes.length : 0;
    await origRun.call(this, r, target, baseR, context);
    var kids = Array.from((r && r.children) || []);
    for (var i = 0; i < kids.length; i++) {
      var name = localName(kids[i]);
      if (name === 'oMath' || name === 'oMathPara') appendFormula(kids[i], target);
    }
    if (!target) return;
    for (var j = start; j < target.childNodes.length; j++) {
      var el = target.childNodes[j];
      if (!el || el.nodeType !== 1 || !el.textContent) continue;
      var src = el.textContent;
      var next = flattenQuotedFrac(src);
      var cleanRun = typeof window.cnlCleanPasteText === 'function' ? window.cnlCleanPasteText : null;
      if (cleanRun && (/\\[a-zA-Z]/.test(next) || /\$[^$\n]+\$/.test(next))) {
        try { next = cleanRun(next) || next; } catch (ignore) {}
      }
      if (next && next !== src) el.textContent = next;
    }
  };

  proto.render = async function () {
    var self = this;
    var root = document.createElement('div');
    root.className = 'doc-root';
    var body = typeof first === 'function' ? first(self.document, 'w\\:body, body') : null;
    if (!body) throw new Error('document.xml has no body.');
    for (var i = 0; i < body.children.length; i++) {
      var child = body.children[i];
      var name = localName(child);
      if (name === 'p') {
        var node = await self.renderParagraph(child);
        if (node) root.appendChild(node);
      } else if (name === 'tbl') {
        var tbl = await self.renderTable(child);
        if (tbl) {
          root.appendChild(tbl);
          self.report.tables++;
        }
      } else if (name === 'oMath' || name === 'oMathPara') {
        var wrap = document.createElement('div');
        wrap.className = 'doc-p';
        appendFormula(child, wrap);
        if (wrap.textContent.trim()) {
          var block = document.createElement('div');
          block.className = 'doc-block';
          block.appendChild(wrap);
          root.appendChild(block);
        }
      }
    }
    self.applyCompactSpacing(root);
    self.applyFixedPalette(root);
    return root;
  };
})();

window.CortexDocx = DocxPrototype;
window.cortexReleaseImages = revokeObjectUrls;
