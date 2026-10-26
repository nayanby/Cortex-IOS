/*
 * Injected at document start, before any page script runs.
 *
 * Three page behaviours do not work inside a WebView and are repaired here:
 *
 *  - WebView silently ignores anchor clicks that carry a download attribute, so
 *    every export in the page (formatted DOCX, backup ZIP, generated AI
 *    documents) would appear to do nothing. All of those paths funnel through
 *    URL.createObjectURL + a.click(), which lets us intercept them in one place
 *    and hand the bytes to Android instead.
 *
 *  - The page stores AI posters and its heading read-log through
 *    POST /api/poster and reads them back with GET /api/poster?doc=&documentKey=&scope=.
 *    WebViewAssetLoader strips query strings from the path it hands a
 *    PathHandler and never routes POST bodies to one at all, so both directions
 *    are served from Room through the Java bridge instead.
 *
 *  - The page draws its own header and its own per-card edit buttons, both of
 *    which the app replaces with native ones. This script keeps the replacements
 *    wired to the page: it reports which view is showing and which subject is
 *    open so the toolbar can follow, gives every subject and chapter card one
 *    native edit button, and names the card that button belongs to when it is
 *    tapped.
 *
 *  - Uploading starts from a native folder screen that already knows which
 *    folder the document belongs in, so when the page's folder chooser appears
 *    this script answers it with that folder instead of making the user pick.
 *
 *  - The reader's type controls (size, line and paragraph spacing) live in the
 *    toolbar, but the note's own point sizes are inline on every run, so the
 *    restyling happens here, element by element, after each render.
 *
 *  - The page paints its tables inline with !important, which no stylesheet
 *    outranks however specific or late it is, so the look the notes' tables
 *    wear is written the same way: inline, after each render.
 *
 *  - The page moves its current-heading index only when something is tapped,
 *    but the reader's bar names the heading being read, so the scroll is
 *    watched here and the index is moved by the rule the bar follows.
 */
(function () {
  if (window.__clinicalNotesBridge) return;
  window.__clinicalNotesBridge = true;

  var bridge = window.AndroidBridge;
  if (!bridge) return;

  var nativeFetch = window.fetch.bind(window);
  var nativeClick = HTMLAnchorElement.prototype.click;

  // 768 KiB. A multiple of 3 so each chunk base64-encodes independently and
  // the pieces concatenate into one valid stream on the Android side.
  var CHUNK_BYTES = 786432;
  var ENCODE_STEP = 32768;

  var POSTER_ENDPOINT = '/api/poster';

  var EDIT_BUTTON_CLASS = 'native-edit-btn';
  var EDIT_BUTTON_LABEL = '\u22EE';

  // The notes' tables wear the poster's table look: its grey hairline, and a
  // round of the same size, which one CSS pixel and ten of them come to here.
  var TABLE_EDGE = '1px';
  var TABLE_LINE = '#AEAAAA';
  var TABLE_RADIUS = '10px';
  var TABLE_PAD = '4px 10px';

  // Both grids are part of the page's static markup, but this script runs
  // before that markup is parsed, so arming is retried until they turn up.
  var ARM_ATTEMPTS = 20;
  var ARM_DELAY_MS = 300;

  // armed and watched record, per grid, whether it has been found yet and
  // whether its render observer is attached.
  var GRIDS = [
    { id: 'subjectGrid', card: 'subject-card', name: 'subject-name', kind: 'subject', armed: false, watched: false },
    { id: 'chapterGrid', card: 'chapter-card', name: 'chapter-name', kind: 'chapter', armed: false, watched: false }
  ];

  var FOLDER_CHOOSER_ID = 'folderModalBackdrop';
  var folderChooserWatched = false;
  var textStyleWatched = false;

  function toBase64(bytes) {
    var text = '';
    for (var i = 0; i < bytes.length; i += ENCODE_STEP) {
      var end = Math.min(i + ENCODE_STEP, bytes.length);
      text += String.fromCharCode.apply(null, bytes.subarray(i, end));
    }
    return btoa(text);
  }

  function handOff(blobUrl, fileName) {
    nativeFetch(blobUrl)
      .then(function (response) {
        if (!response.ok) throw new Error('Could not read ' + blobUrl);
        return response.blob();
      })
      .then(function (blob) {
        return blob.arrayBuffer().then(function (arrayBuffer) {
          return { blob: blob, bytes: new Uint8Array(arrayBuffer) };
        });
      })
      .then(function (payload) {
        if (!payload.bytes.length) {
          bridge.saveBlobCancel();
          return;
        }
        bridge.saveBlobStart(fileName, payload.blob.type || 'application/octet-stream');
        for (var i = 0; i < payload.bytes.length; i += CHUNK_BYTES) {
          var end = Math.min(i + CHUNK_BYTES, payload.bytes.length);
          bridge.saveBlobChunk(toBase64(payload.bytes.subarray(i, end)));
        }
        bridge.saveBlobFinish();
      })
      .catch(function (error) {
        bridge.saveBlobCancel();
        console.error('Android export failed:', error);
      });
  }

  function pathOf(url) {
    var path = String(url).split('?')[0].split('#')[0];
    var scheme = path.indexOf('://');
    if (scheme !== -1) {
      var slash = path.indexOf('/', scheme + 3);
      path = slash === -1 ? '' : path.slice(slash);
    }
    return path;
  }

  function isPosterUrl(url) {
    return pathOf(url) === POSTER_ENDPOINT;
  }

  function jsonResponse(body, status, statusText) {
    return new Response(body, {
      status: status,
      statusText: statusText,
      headers: { 'Content-Type': 'application/json' }
    });
  }

  function requestText(input, init) {
    var body = init && init.body != null
      ? init.body
      : (typeof input === 'string' ? null : input);

    if (typeof body === 'string') return Promise.resolve(body);
    if (body && typeof body.text === 'function') return body.text();
    return Promise.resolve(String(body == null ? '' : body));
  }

  // The page keys a saved payload as `${documentKey}::${scopeKey}`, matching the
  // layout of its own embedded snapshot, so a migrated snapshot and a
  // bridge-saved poster land on the same row.
  function posterGet(url) {
    var params = new URLSearchParams(String(url).split('?')[1] || '');
    var documentKey = params.get('documentKey') || '';
    var scope = params.get('scope') || '';
    var payload = bridge.posterGet(documentKey + '::' + scope);
    if ((payload === null || payload === undefined) && bridge.posterFind) {
      payload = bridge.posterFind(documentKey, scope, params.get('doc') || '');
    }
    return payload === null || payload === undefined
      ? jsonResponse('', 404, 'Not Found')
      : jsonResponse(payload, 200, 'OK');
  }

  function posterPut(input, init) {
    return requestText(input, init).then(function (body) {
      var parsed = JSON.parse(body);
      var payload = parsed.poster;

      if (payload === null || payload === undefined) {
        return jsonResponse('{"error":"Missing poster payload."}', 400, 'Bad Request');
      }

      var key = String(parsed.documentKey || '') + '::' + String(parsed.scope || '');
      return bridge.posterPut(key, JSON.stringify(payload))
        ? jsonResponse('{"ok":true}', 200, 'OK')
        : jsonResponse('{"error":"Could not save poster."}', 500, 'Internal Server Error');
    }).catch(function () {
      return jsonResponse('{"error":"Malformed poster payload."}', 400, 'Bad Request');
    });
  }

  window.fetch = function (input, init) {
    var url = typeof input === 'string' ? input : (input && input.url) || '';

    if (!isPosterUrl(url)) return nativeFetch(input, init);

    var method = String(
      (init && init.method) || (typeof input !== 'string' && input.method) || 'GET'
    ).toUpperCase();

    return method === 'POST'
      ? posterPut(input, init)
      : Promise.resolve(posterGet(url));
  };

  var viewWatched = false;
  var lastView = null;
  var lastTitle = null;
  var lastSubject = null;

  /** 'home', 'subject' or 'reader', from the body class setAppView maintains. */
  function viewOf(body) {
    var classes = String(body.className || '');
    if (classes.indexOf('view-reader') !== -1) return 'reader';
    if (classes.indexOf('view-subject') !== -1) return 'subject';
    return 'home';
  }

  function titleOf(view) {
    // Home keeps the app name, which Android supplies itself.
    if (view === 'home') return '';

    // In the reader the breadcrumb names the subject, so the document's own
    // name has to come from #filename, which the page keeps current even though
    // it leaves the element hidden.
    var node = document.getElementById(view === 'reader' ? 'filename' : 'subjectTitle');
    var text = node ? node.textContent.trim() : '';
    if (text && text !== 'No document loaded') return text;

    var crumb = document.getElementById('breadcrumb');
    return crumb ? crumb.textContent.trim() : '';
  }

  function reportView() {
    var view = viewOf(document.body);
    var title = titleOf(view);
    var subject = subjectName();
    if (view === lastView && title === lastTitle && subject === lastSubject) return;
    lastView = view;
    lastTitle = title;
    lastSubject = subject;
    console.info('[cnl] view ' + view);
    bridge.onViewChanged(view, title, subject);
  }

  function watchPage() {
    var observer = new MutationObserver(reportView);
    observer.observe(document.body, { attributes: true, attributeFilter: ['class'] });

    ['filename', 'subjectTitle', 'breadcrumb'].forEach(function (id) {
      var node = document.getElementById(id);
      if (node) observer.observe(node, { childList: true, characterData: true, subtree: true });
    });

    reportView();
  }

  function editButton(card, spec) {
    var button = document.createElement('button');
    button.type = 'button';
    button.className = EDIT_BUTTON_CLASS;
    button.setAttribute('aria-label', 'Edit ' + spec.kind);
    button.textContent = EDIT_BUTTON_LABEL;

    button.addEventListener('click', function (event) {
      // The card's own handler opens the document and only ignores clicks on
      // .card-action, so stopping the event here is what keeps raising the menu
      // from also navigating.
      event.preventDefault();
      event.stopPropagation();

      var name = card.querySelector('.' + spec.name);
      // A chapter name alone is not enough to find it: two subjects can hold one.
      var subject = spec.kind === 'chapter' ? subjectName() : '';
      bridge.openEditMenu(spec.kind, name ? name.textContent.trim() : '', subject);
    });

    return button;
  }

  function subjectName() {
    var node = document.getElementById('subjectTitle');
    return node ? node.textContent.trim() : '';
  }

  function addEditButtons(grid, spec) {
    var cards = grid.getElementsByClassName(spec.card);
    for (var i = 0; i < cards.length; i++) {
      if (cards[i].querySelector('.' + EDIT_BUTTON_CLASS)) continue;
      cards[i].appendChild(editButton(cards[i], spec));
    }
  }

  function armGrid(spec) {
    var grid = document.getElementById(spec.id);
    if (!grid) return false;

    if (!spec.watched) {
      spec.watched = true;
      // Both render functions replace the grid's children wholesale, so the
      // buttons have to be added again after every render. Only the grid's own
      // child list is observed: adding a button touches a card, not the grid,
      // so the observer cannot feed itself.
      new MutationObserver(function () { addEditButtons(grid, spec); })
        .observe(grid, { childList: true });
    }

    addEditButtons(grid, spec);
    return true;
  }

  function armFolderChooser() {
    var backdrop = document.getElementById(FOLDER_CHOOSER_ID);
    if (!backdrop) return false;

    new MutationObserver(function () {
      if (!backdrop.classList.contains('show')) return;
      var subject = window.__cnlUploadSubject;
      if (!subject) return;
      window.__cnlUploadSubject = '';
      // The chooser fills its folder list just before it shows, but focus()
      // is queued after us, so answering one tick later is safe either way.
      setTimeout(function () { answerFolderChooser(subject); }, 0);
    }).observe(backdrop, { attributes: true, attributeFilter: ['class'] });
    return true;
  }

  function answerFolderChooser(subject) {
    var select = document.getElementById('existingFolderSelect');
    var input = document.getElementById('newFolderInput');
    var confirm = document.getElementById('confirmFolderBtn');
    if (!confirm) return;

    var hasOption = select && Array.prototype.some.call(
      select.options,
      function (option) { return option.value === subject; }
    );

    if (hasOption) {
      select.value = subject;
    } else if (input) {
      if (select) select.value = '';
      input.value = subject;
    }
    confirm.click();
  }

  // --- reader type: size, line spacing, paragraph spacing ------------------
  // The DOCX renderer writes Word's own point sizes inline onto runs and
  // headings, so no stylesheet variable can scale them: each element's size is
  // measured once, remembered, and multiplied from there. Tables are skipped
  // outright - their columns are laid out for the size they were written at.
  var TEXT_STYLE_KEY = 'cnlTextStyleV5';
  // The key moved with the model: a store written under the old percents would
  // read here as absurd point deltas. font is points to add to each written
  // size; line is the leading in times of what is written; para is the air
  // around a paragraph as a part of the leading.
  var textStyle = { font: 0, line: 1.4375, para: 0.16 };
  try {
    // Android seeds the live Aa prefs at document-start so the first style
    // pass never flashes the written size before SharedPreferences arrive.
    var seed = window.__CNL_TEXT_STYLE__;
    if (seed && typeof seed.font === 'number') {
      textStyle.font = seed.font;
      textStyle.line = typeof seed.line === 'number' && seed.line > 0 ? seed.line : textStyle.line;
      textStyle.para = typeof seed.para === 'number' && seed.para > 0 ? seed.para : textStyle.para;
    } else {
      var storedStyle = JSON.parse(localStorage.getItem(TEXT_STYLE_KEY) || 'null');
      if (storedStyle && typeof storedStyle.font === 'number') {
        textStyle.font = storedStyle.font;
        textStyle.line = storedStyle.line > 0 ? storedStyle.line : textStyle.line;
        textStyle.para = storedStyle.para > 0 ? storedStyle.para : textStyle.para;
      }
    }
  } catch (error) {
    // An unreadable store just means the defaults.
  }

  function saveTextStyle() {
    try {
      localStorage.setItem(TEXT_STYLE_KEY, JSON.stringify(textStyle));
    } catch (error) {
      // Private mode or a full store: the session still gets the style.
    }
  }

  // The pass is skipped outright while the paper holds the same tree, with the
  // same number of nodes, at the same scale. Reopening a note re-attaches the
  // tree the page kept, and measuring every paragraph of it again cost as much
  // as building the note did.
  var styledRoot = null;
  var styledNodes = -1;
  var styledScale = '';

  function scaleOf() {
    // Bump when margin/table rules change so a warm tree is restyled.
    return 'v17|' + textStyle.font + '|' + textStyle.line + '|' + textStyle.para;
  }

  var RING = '\u26AC';

  function wrapCalibriGlyphs(root) {
    if (!root) return;
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
    var nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i];
      var text = node.nodeValue;
      if (!text || text.indexOf(RING) < 0) continue;
      var parent = node.parentNode;
      if (!parent || (parent.classList && parent.classList.contains('cnl-glyph-calibri'))) continue;
      var parts = text.split(RING);
      var frag = document.createDocumentFragment();
      for (var p = 0; p < parts.length; p++) {
        if (parts[p]) frag.appendChild(document.createTextNode(parts[p]));
        if (p < parts.length - 1) {
          var span = document.createElement('span');
          span.className = 'cnl-glyph-calibri';
          span.textContent = RING;
          frag.appendChild(span);
        }
      }
      parent.replaceChild(frag, node);
    }
  }

  // BS2/BS3 use fixed 14px padding above; other consecutive headings use 8px.
  function styleHeadingSpacing(paper) {
    if (window.cnlClearHeadingIndents) window.cnlClearHeadingIndents(paper);
    var gap = textStyle.para / 0.16;
    var blocks = paper.querySelectorAll('.doc-block,table');
    var previousHeading = false;
    var previousContent = null;
    for (var i = 0; i < blocks.length; i++) {
      var block = blocks[i];
      if (block.tagName !== 'TABLE' && block.closest('table')) continue;
      if (!block.matches('.h1,.h2,.h3,.h4,.boldside1,.boldside2,.boldside3')) {
        previousHeading = false;
        previousContent = block;
        continue;
      }
      var fixedBefore = block.matches('.boldside2,.boldside3');
      if (fixedBefore && previousContent) {
        // A non-collapsing 14px gap replaces all preceding trailing air.
        previousContent.style.setProperty('margin-bottom', '0px', 'important');
        if (previousContent.classList.contains('doc-block')) {
          previousContent.style.setProperty('padding-bottom', '0px', 'important');
          var previousParagraph = previousContent.querySelector(':scope > .doc-p');
          if (previousParagraph) previousParagraph.style.setProperty('margin-bottom', '0px', 'important');
        }
        var previousBox = previousContent.parentElement;
        if (previousBox && previousContent === previousBox.lastElementChild &&
            previousBox.matches('.cnl-bs-section,.cnl-table-box,.cnl-section-table-box') && !previousBox.contains(block)) {
          previousBox.style.setProperty('margin-bottom', '0px', 'important');
          if (previousBox.classList.contains('cnl-bs-section')) previousBox.style.setProperty('padding-bottom', '0px', 'important');
        }
      }
      block.style.setProperty('margin-top', (fixedBefore || previousHeading ? 0 : 10 * gap) + 'px', 'important');
      previousHeading = true;
      previousContent = block;
      block.style.setProperty('margin-bottom', 8 * gap + 'px', 'important');
      block.style.setProperty('padding-top', (fixedBefore ? 14 : 0) + 'px', 'important');
      block.style.setProperty('padding-bottom', '0px', 'important');
      var heading = block.querySelector(':scope > .doc-p');
      if (heading) {
        if (block.matches('.boldside1,.boldside2,.boldside3')) {
          heading.style.setProperty('padding-left', (fixedBefore ? 2 : 0) + 'px', 'important');
        }
        heading.style.setProperty('margin-top', '0px', 'important');
        heading.style.setProperty('margin-bottom', '0px', 'important');
        if (block.matches('.h1,.h2,.h3')) {
          heading.style.setProperty('padding', '6px', 'important');
        } else {
          heading.style.setProperty('padding-top', '0px', 'important');
          heading.style.setProperty('padding-bottom', '0px', 'important');
        }
      }
    }
    var sections = paper.getElementsByClassName('cnl-bs-section');
    for (var s = 0; s < sections.length; s++) {
      sections[s].style.setProperty('margin-top', '0px', 'important');
      var last = sections[s].lastElementChild;
      if (last && last.matches('.doc-block.h1,.doc-block.h2,.doc-block.h3,.doc-block.h4,.doc-block.boldside1,.doc-block.boldside2,.doc-block.boldside3')) {
        sections[s].style.setProperty('margin-bottom', '0px', 'important');
        sections[s].style.setProperty('padding-bottom', '0px', 'important');
      }
    }
    if (window.cnlIndentHeadingPrefixes) window.cnlIndentHeadingPrefixes(paper);
  }

  /** Restyles the note, and says whether there was anything to restyle. */
  function stylePaper() {
    var paper = document.getElementById('paper');
    if (!paper) return false;
    if (window.cnlReadingBeforeStyle) window.cnlReadingBeforeStyle();
    wrapCalibriGlyphs(paper);

    var root = paper.firstElementChild;
    var scale = scaleOf();
    var count = paper.getElementsByTagName('*').length;
    if (root && root === styledRoot && count === styledNodes && scale === styledScale) return false;

    // A point is 4/3 px on the page's 96dpi canvas.
    var fontDeltaPx = textStyle.font * 4 / 3;
    var lineTimes = textStyle.line;
    var paraScale = 1 + textStyle.para;

    var nodes = [paper].concat(Array.prototype.slice.call(paper.getElementsByTagName('*')));

    // Every base is read before any size is written: a node that inherits its
    // size would otherwise measure a parent this pass has already scaled, and
    // scale twice. The base is held on the node itself rather than in a data
    // attribute, because writing an attribute dirties that node's style and the
    // next measurement would have to resolve it all over again.
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i];
      if (node.__cnlTypeBase || (node.closest && node.closest('table'))) continue;
      var computed = getComputedStyle(node);
      node.__cnlTypeBase = computed.fontSize + '|' + computed.lineHeight +
        '|' + computed.marginTop + '|' + computed.marginBottom;
    }

    for (var j = 0; j < nodes.length; j++) {
      var el = nodes[j];
      if (el.closest && el.closest('table')) continue;

      var parts = el.__cnlTypeBase.split('|');
      var baseSize = parseFloat(parts[0]);
      var baseLine = parseFloat(parts[1]);
      var baseTop = parseFloat(parts[2]);
      var baseBottom = parseFloat(parts[3]);
      var newSize = baseSize > 0 ? baseSize + fontDeltaPx : 0;
      var fontRatio = baseSize > 0 ? newSize / baseSize : 1;
      var isPara = el.classList && el.classList.contains('doc-p');
      var isBlock = el.classList && el.classList.contains('doc-block');
      var headingSel = '.h1,.h2,.h3,.h4,.boldside1,.boldside2,.boldside3,.word-h1,.word-h2,.word-h3,.word-h4,.word-boldside1,.word-boldside2,.word-boldside3';
      var isHeading = !!(el.classList && (
        el.classList.contains('h1') || el.classList.contains('h2') ||
        el.classList.contains('h3') || el.classList.contains('h4') ||
        el.classList.contains('boldside1') || el.classList.contains('boldside2') ||
        el.classList.contains('boldside3')
      )) || !!(el.closest && el.closest(headingSel));
      // The page pins some of its own sizes with !important, which an ordinary
      // inline style loses to. Leading follows the size, or enlarged text would
      // sit on the leading it was written with and collide.
      if (baseSize > 0) {
        el.style.setProperty(
          'font-size',
          newSize + 'px',
          'important'
        );
      }
      var lineRatio = lineTimes / 1.5;
      var leading = newSize * (isHeading ? 1.125 : 1.5) * lineRatio;
      if (newSize > 0) el.style.setProperty('line-height', leading + 'px', 'important');
      if (newSize > 0 && el.classList && el.classList.contains('doc-list')) {
        el.style.setProperty('--cnl-list-first-line-height', leading + 'px');
      }

      // Body paragraphs and bullets: drop Word/page before/after air (margins
      // and .doc-block padding). Only Aa paragraph air is added. Headings keep
      // the page's own spacing.
      var added = (isPara || (isBlock && !isHeading)) && baseLine > 0
        ? baseLine * fontRatio * textStyle.para
        : 0;
      if ((isPara || isBlock) && !isHeading) {
        el.style.setProperty('margin-top', '0px', 'important');
        el.style.setProperty('margin-bottom', '0px', 'important');
        if (isBlock && !isHeading) {
          var listEl = el.querySelector(':scope > .doc-list, :scope > .doc-p.doc-list');
          var previous = el.previousElementSibling;
          var next = el.nextElementSibling;
          var previousList = previous && previous.querySelector(':scope > .doc-list');
          var nextList = next && next.querySelector(':scope > .doc-list');
          var gap = textStyle.para / 0.16;
          // Flat Word list blocks form one list across consecutive siblings.
          el.style.setProperty('padding-top', (listEl ? 0 : 0.05 * newSize) + 'px', 'important');
          el.style.setProperty('padding-bottom', (listEl ? 6 : 14) * gap + 'px', 'important');
          el.style.setProperty('margin-bottom', '0px', 'important');
        } else if (isPara) {
          var inBlock = el.parentElement && el.parentElement.classList.contains('doc-block');
          el.style.setProperty('margin-top', (inBlock ? 0 : added) + 'px', 'important');
          el.style.setProperty('margin-bottom', (inBlock ? 0 : 14 * textStyle.para / 0.16) + 'px', 'important');
        }
      } else if (baseTop > 0 || baseBottom > 0) {
        var top = (baseTop > 0 ? baseTop * paraScale : 0);
        var bottom = (baseBottom > 0 ? baseBottom * paraScale : 0);
        if (baseTop > 0) {
          if (top > 0) el.style.setProperty('margin-top', top + 'px', 'important');
          else el.style.setProperty('margin-top', '0px', 'important');
        }
        if (baseBottom > 0) {
          if (bottom > 0) el.style.setProperty('margin-bottom', bottom + 'px', 'important');
          else el.style.setProperty('margin-bottom', '0px', 'important');
        }
      }
    }

    styleHeadingSpacing(paper);
    if (window.cnlAlignBulletMarkers) window.cnlAlignBulletMarkers(paper);
    styledRoot = root;
    styledNodes = count;
    styledScale = scale;
    return true;
  }

  var styleQueued = false;
  function queueStyle() {
    if (styleQueued) return;
    styleQueued = true;
    // Next frame — not an 80ms wait — so a newly opened note is scaled before
    // the reader overlay lifts and the user never sees Word's 100% size first.
    requestAnimationFrame(function () {
      styleQueued = false;
      var started = performance.now();
      var paper = document.getElementById('paper');
      if (paper) {
        compactDocumentBreaks(paper);
        sectionPaper(paper);
        wrapSectionTables(paper);
        wrapStandaloneTables(paper);
        restartNumberedLists(paper);
      }
      stylePaper();
      if (paper) {
        styleImages(paper);
        markImageOnlyParagraphs(paper);
      }
      styleTables();
      if (paper) {
        styleSections(paper);


      }
      console.info('[cnl] note style in ' + Math.round(performance.now() - started) + 'ms');
    });
  }

  function styleImages(paper) {
    var images = paper.querySelectorAll('img');
    for (var i = 0; i < images.length; i++) {
      var image = images[i];
      image.style.setProperty('float', 'none', 'important');
      image.style.setProperty('position', 'static', 'important');
      image.style.setProperty('display', 'block', 'important');
      image.style.setProperty('margin-left', 'auto', 'important');
      image.style.setProperty('margin-right', 'auto', 'important');
      image.style.setProperty('max-width', '100%', 'important');
      image.style.setProperty('height', 'auto', 'important');
    }
  }

  function markImageOnlyParagraphs(paper) {
    var blocks = paper.querySelectorAll('.doc-block, li');
    for (var i = 0; i < blocks.length; i++) {
      var block = blocks[i];
      if (!block.querySelector('img')) continue;
      var text = '';
      var walker = document.createTreeWalker(block, NodeFilter.SHOW_TEXT, null);
      while (walker.nextNode()) {
        if (walker.currentNode.parentElement.closest('.list-marker')) continue;
        text += walker.currentNode.nodeValue || '';
      }
      if (text.trim()) continue;
      block.classList.add('cnl-image-only');
    }
  }

  // A turn of the device changes the width every table was measured against,
  // and no mutation follows it, so the pass is asked for again here.
  window.addEventListener('resize', queueStyle);

  // The notes' tables wear the poster's table look: one hairline grey outside
  // and between the cells, round corners, and a header row centred in its own
  // height. The page writes its palette for these as inline !important styles,
  // which outrank any stylesheet however specific or late, so the look has to
  // be written the same way it is fought - inline, after each render.
  function styleTables() {
    var paper = document.getElementById('paper');
    if (!paper) return;

    var edge = TABLE_EDGE + ' solid ' + TABLE_LINE;
    var tables = paper.getElementsByTagName('table');

    for (var i = 0; i < tables.length; i++) {
      var table = tables[i];
      // Let the table use its intrinsic content width, capped by its container;
      // this keeps short columns compact instead of stretching every column.
      table.style.setProperty('table-layout', 'auto', 'important');
      table.style.setProperty('max-width', 'none', 'important');
      table.style.setProperty('width', '100%', 'important');
      table.style.setProperty('margin-left', 'auto', 'important');
      table.style.setProperty('margin-right', 'auto', 'important');
      table.style.setProperty('margin-top', '0', 'important');
      table.style.setProperty('margin-bottom', '0', 'important');

      // A radius only holds with separate borders, and the clip is what rounds
      // the header's own square corners into the table's.
      table.style.setProperty('border-collapse', 'separate', 'important');
      table.style.setProperty('border-spacing', '0', 'important');
      table.style.setProperty('border', edge, 'important');
      table.style.setProperty('border-color', TABLE_LINE, 'important');
      table.style.setProperty('border-radius', TABLE_RADIUS, 'important');
      table.style.setProperty('overflow', 'hidden', 'important');

      var rows = table.rows;
      for (var r = 0; r < rows.length; r++) {
        var cells = rows[r].cells;
        var lastRow = r === rows.length - 1;
        for (var c = 0; c < cells.length; c++) {
          var cell = cells[c];
          // Only the lines between cells are drawn here: the last column and
          // the last row carry none, so the table's own border is the outside
          // edge and no doubled line forms anywhere.
          cell.style.setProperty('border-top', '0', 'important');
          cell.style.setProperty('border-left', '0', 'important');
          cell.style.setProperty('border-right', c === cells.length - 1 ? '0' : edge, 'important');
          cell.style.setProperty('border-bottom', lastRow ? '0' : edge, 'important');
          cell.style.setProperty('border-color', TABLE_LINE, 'important');
          cell.style.setProperty('padding', TABLE_PAD, 'important');
          cell.style.setProperty('overflow-wrap', 'normal', 'important');
          cell.style.setProperty('word-break', 'normal', 'important');
          // Intrinsic minimum includes the longest unbroken word and cell padding.
          cell.style.setProperty('min-width', 'min-content', 'important');
          cell.style.setProperty('max-width', 'none', 'important');
          // Match the body-relative size even before the final typography pass.
          var tableScale = Number(window.__CNL_TEXT_STYLE__ && window.__CNL_TEXT_STYLE__.systemFontScale) || 1;
          var tablePx = (Math.max(14, 17 - 2 / 3 + textStyle.font * 4 / 3) - 4 / 3) * tableScale;
          var tableSize = tablePx + 'px';
          cell.style.setProperty('font-size', tableSize, 'important');
          cell.style.setProperty('line-height', '1.3', 'important');
          var runs = cell.getElementsByTagName('*');
          for (var d = 0; d < runs.length; d++) {
            var run = runs[d];
            run.style.setProperty('font-size', tableSize, 'important');
            run.style.setProperty('line-height', '1.3', 'important');
            if (run.classList && run.classList.contains('doc-p')) {
              run.style.setProperty('margin-top', '0', 'important');
              run.style.setProperty('margin-bottom', '2pt', 'important');
            }
          }
          if (r === 0) cell.style.setProperty('vertical-align', 'middle', 'important');
        }
      }

      // Native min-content layout considers every cell, its padding, and spans.
      table.style.setProperty('min-width', 'min-content', 'important');

    }
  }

  function compactDocumentBreaks(root) {
    var emptyBlocks = root.querySelectorAll('.doc-p, p');
    for (var i = emptyBlocks.length - 1; i >= 0; i--) {
      var block = emptyBlocks[i];
      if (block.textContent.trim() === '' &&
          !block.querySelector('img, svg, table, input, video, audio, canvas')) {
        block.remove();
      }
    }

    // Removing an empty paragraph must also remove its padded Word row.
    root.querySelectorAll('.doc-block').forEach(function (block) {
      if (!block.textContent.trim() &&
          !block.querySelector('img,svg,table,input,video,audio,canvas,[id],a[name]')) {
        block.remove();
      }
    });

    var elements = [root].concat(Array.prototype.slice.call(root.querySelectorAll('*')));
    for (var e = elements.length - 1; e >= 0; e--) {
      var element = elements[e];
      var style = element.getAttribute('style') || '';
      var classes = element.getAttribute('class') || '';
      var isPageBreak = /page[-_]?break/i.test(classes) ||
        /page-break-(before|after)\s*:\s*(always|left|right)|break-(before|after)\s*:\s*page/i.test(style);
      if (isPageBreak && element.textContent.trim() === '' &&
          !element.querySelector('img, svg, table, input, video, audio, canvas')) {
        element.remove();
        continue;
      }
      if (element.tagName.toLowerCase() === 'br' && isPageBreak) {
        element.remove();
        continue;
      }
      element.style.setProperty('break-before', 'auto', 'important');
      element.style.setProperty('break-after', 'auto', 'important');
      element.style.setProperty('break-inside', 'auto', 'important');
      element.style.setProperty('page-break-before', 'auto', 'important');
      element.style.setProperty('page-break-after', 'auto', 'important');
      element.style.setProperty('page-break-inside', 'auto', 'important');
    }

    var breaks = root.querySelectorAll('br');
    for (var brIndex = 0; brIndex < breaks.length; brIndex++) {
      var lineBreak = breaks[brIndex];
      if (!lineBreak.parentNode) continue;
      var previous = lineBreak.previousSibling;
      while (previous && previous.nodeType === Node.TEXT_NODE && !previous.nodeValue.trim()) {
        previous = previous.previousSibling;
      }
      if (previous && previous.nodeType === Node.ELEMENT_NODE &&
          previous.tagName.toLowerCase() === 'br') {
        lineBreak.remove();
      }
    }
  }

  // --- bold side headings as snapshot sections ------------------------------
  // A snapshot reads as a run of shaded sections, each opening on a coloured
  // head band, and the notes are drawn the same way: a first-level bold side
  // heading takes a band, and everything under it down to the next heading sits
  // in that band's box. The levels below it are headings within a section, as
  // they are on a snapshot, so they keep their own look and stay in the box.
  //
  // The page has no such wrapper, so one is put in after each render; the tones
  // alternate section to section exactly as a snapshot's do.
  var SECTION_CLASS = 'cnl-bs-section';
  var TABLE_BOX_CLASS = 'cnl-table-box';
  var SECTION_TABLE_BOX_CLASS = 'cnl-section-table-box';
  var SECTION_HEAD = '.doc-block.boldside1, .doc-block.h4';
  // A section ends at the next section head, or at any Word heading above it.
  var SECTION_END = '.doc-block.h1, .doc-block.h2, .doc-block.h3, ' +
    SECTION_HEAD;
  // The head's own air, as a share of its type: what it keeps above itself, and
  // the narrower gap between its underline and the first line under it.
  var BAND_PAD = 0.42;
  var HEAD_GAP = 0.14;
  // How far a section holds its content off the box's edges; the same figure the
  // stylesheet insets the blocks by.
  var SECTION_INSET = 12;
  var TABLE_INSET = 2;

  /** Wraps each bold side heading and the blocks under it in one section. */
  function sectionPaper(paper) {
    return;
    var heads = paper.querySelectorAll(SECTION_HEAD);
    for (var i = 0; i < heads.length; i++) {
      var head = heads[i];
      var parent = head.parentNode;
      if (!parent || (parent.classList && parent.classList.contains(SECTION_CLASS))) continue;

      var section = document.createElement('div');
      section.className = SECTION_CLASS;
      parent.insertBefore(section, head);

      var node = head;
      while (node) {
        var next = node.nextElementSibling;
        section.appendChild(node);
        if (!next || !next.matches || next.matches(SECTION_END) ||
          next.classList.contains(SECTION_CLASS)) {
          break;
        }
        node = next;
      }
    }

    // Tone is a section's place in the note, not its heading level, so two
    // sections never touch in the same colour.
    var sections = paper.getElementsByClassName(SECTION_CLASS);
    for (var s = 0; s < sections.length; s++) {
      sections[s].setAttribute('data-tone', s % 2 ? '1' : '0');
    }
  }

  /** Gives standalone tables their own rounded box; section tables use theirs. */
  function wrapStandaloneTables(paper) {
    var tables = paper.getElementsByTagName('table');
    var standaloneIndex = 0;
    for (var i = 0; i < tables.length; i++) {
      var table = tables[i];
      var parentTable = table.parentElement && table.parentElement.closest
        ? table.parentElement.closest('table')
        : null;
      if ((table.closest && table.closest('.' + SECTION_CLASS)) ||
        (table.closest && table.closest('.' + TABLE_BOX_CLASS)) || parentTable) {
        continue;
      }
      var box = document.createElement('div');
      box.className = TABLE_BOX_CLASS;
      box.setAttribute('data-tone', standaloneIndex++ % 2 ? '1' : '0');
      table.parentNode.insertBefore(box, table);
      box.appendChild(table);
    }
  }

  /** Insets tables inside section boxes without changing their section styling. */
  function wrapSectionTables(paper) {
    var tables = paper.getElementsByTagName('table');
    for (var i = 0; i < tables.length; i++) {
      var table = tables[i];
      var section = table.closest ? table.closest('.' + SECTION_CLASS) : null;
      var parentTable = table.parentElement && table.parentElement.closest
        ? table.parentElement.closest('table')
        : null;
      if (!section || (table.closest && table.closest('.' + SECTION_TABLE_BOX_CLASS)) ||
        parentTable) {
        continue;
      }
      var box = document.createElement('div');
      box.className = SECTION_TABLE_BOX_CLASS;
      table.parentNode.insertBefore(box, table);
      box.appendChild(table);
    }
  }

  /** Restarts numbered sequences after any non-list content, even if source numbering continues. */
  function restartNumberedLists(paper) {
    var blocks = paper.querySelectorAll('.doc-block');
    var nextNumber = 1;
    for (var i = 0; i < blocks.length; i++) {
      var block = blocks[i];
      var list = block.querySelector(':scope > .doc-list, :scope > .doc-p.doc-list');
      if (!list) {
        nextNumber = 1;
        continue;
      }

      var markers = list.querySelectorAll('.list-marker.is-number');
      var orderedLists = list.matches && list.matches('ol')
        ? [list]
        : list.querySelectorAll('ol');
      var isNumbered = markers.length > 0 || orderedLists.length > 0;
      var level = list.getAttribute('data-list-level');
      var isAllowedBullet = !isNumbered &&
        (level === '0' || level === '1') &&
        list.querySelector('.list-marker.is-bullet');

      if (!isNumbered) {
        if (!isAllowedBullet) nextNumber = 1;
        continue;
      }

      if (markers.length > 0) {
        for (var m = 0; m < markers.length; m++) {
          var marker = markers[m];
          var text = marker.textContent || '';
          var number = /\d+/.exec(text);
          if (number) {
            var replacement = text.slice(0, number.index) + nextNumber +
              text.slice(number.index + number[0].length);
            if (replacement !== text) marker.textContent = replacement;
          } else {
            var parentList = marker.closest && marker.closest('ol');
            if (parentList) parentList.start = nextNumber;
          }
          nextNumber++;
        }
      } else {
        for (var o = 0; o < orderedLists.length; o++) {
          var ordered = orderedLists[o];
          ordered.start = nextNumber;
          nextNumber += ordered.querySelectorAll(':scope > li').length;
        }
      }
    }
  }

  /**
   * A section's air, in the heading's own type so it follows Aa. The band sits
   * flush against the top of the box, so Word's space-before is dropped rather
   * than left to read as a band of colour above it; what is left of that air
   * goes under the band and at the foot of the box instead.
   *
   * Written after the type pass, which is what puts those margins there.
   */
  function styleSections(paper) {
    if (window.cnlClearHeadingIndents) window.cnlClearHeadingIndents(paper);
    var sections = paper.getElementsByClassName(SECTION_CLASS);
    for (var i = 0; i < sections.length; i++) {
      var section = sections[i];
      var head = section.firstElementChild;
      if (!head) continue;
      var size = parseFloat(getComputedStyle(head).fontSize) || 0;
      var pad = (size * BAND_PAD) + 'px';
      var gap = (size * HEAD_GAP) + 'px';
      head.style.setProperty('margin-top', '0px', 'important');
      head.style.setProperty('margin-bottom', '0px', 'important');
      head.style.setProperty('padding-top', pad, 'important');
      head.style.setProperty('padding-bottom', gap, 'important');
      var heading = head.querySelector(':scope > .doc-p.boldside1, :scope > .doc-p.h4');
      head.style.setProperty('border', '0', 'important');
      head.style.setProperty('border-bottom', '0', 'important');
      if (heading) {
        if (head.classList.contains('h4')) {
          head.style.setProperty('background-color', '#28467C', 'important');
          heading.style.setProperty('background', 'transparent', 'important');
          heading.style.setProperty('background-color', 'transparent', 'important');
          heading.style.setProperty('border', '0', 'important');
          heading.style.setProperty('border-bottom', '0', 'important');
          heading.style.setProperty('box-shadow', 'none', 'important');
          heading.style.setProperty('text-decoration', 'none', 'important');
          heading.style.setProperty('color', '#FFFFFF', 'important');
          heading.style.setProperty('padding-left', '12px', 'important');
          heading.style.setProperty('padding-right', '12px', 'important');
          var runs = heading.querySelectorAll('*');
          for (var r = 0; r < runs.length; r++) {
            runs[r].style.setProperty('color', '#FFFFFF', 'important');
            runs[r].style.setProperty('background', 'transparent', 'important');
            runs[r].style.setProperty('background-color', 'transparent', 'important');
          }
        } else if (head.classList.contains('boldside1')) {
          head.style.setProperty('background-color', 'transparent', 'important');
          head.style.setProperty('padding-bottom', '0px', 'important');
          heading.style.setProperty('background', 'transparent', 'important');
          heading.style.setProperty('background-color', 'transparent', 'important');
          heading.style.setProperty('border', '0', 'important');
          heading.style.setProperty('box-shadow', 'none', 'important');
          heading.style.setProperty('color', '#6F3D5D', 'important');
          var runs = heading.querySelectorAll('*');
          for (var r = 0; r < runs.length; r++) {
            runs[r].style.setProperty('color', '#6F3D5D', 'important');
            runs[r].style.setProperty('background', 'transparent', 'important');
            runs[r].style.setProperty('background-color', 'transparent', 'important');
          }
        }
      }
      section.style.setProperty('padding-bottom', pad, 'important');
    }
    styleHeadingSpacing(paper);
    if (window.cnlReadingAfterStyle) window.cnlReadingAfterStyle(paper);
  }

  function convertBoldside3BeforeBoldside(paper) {
    var boldside3s = paper.querySelectorAll('.doc-p.boldside3, .word-boldside3');
    var bs2BasePx = 18;
    var fontDeltaPx = textStyle.font * 4 / 3;
    var lineTimes = textStyle.line;
    var newFontSize = bs2BasePx + fontDeltaPx;
    for (var i = 0; i < boldside3s.length; i++) {
      var el = boldside3s[i];
      var block = el.closest('.doc-block');
      if (!block) continue;
      var next = block.nextElementSibling;
      if (!next) continue;
      var nextIsBoldside = next.classList.contains('boldside1') ||
        next.classList.contains('boldside2') ||
        next.classList.contains('boldside3') ||
        (next.querySelector && (next.querySelector('.boldside1, .boldside2, .boldside3')));
      if (nextIsBoldside) {
        el.classList.remove('boldside3');
        el.classList.add('boldside2');
        if (block.classList.contains('boldside3')) {
          block.classList.remove('boldside3');
          block.classList.add('boldside2');
        }
        el.style.setProperty('font-size', newFontSize + 'px', 'important');
        block.style.setProperty('font-size', newFontSize + 'px', 'important');
        var baseLine = 13 * 4 / 3;
        el.style.setProperty('line-height', (newFontSize * 1.35 * lineTimes / 1.5) + 'px', 'important');
        el.style.setProperty('background', 'transparent', 'important');
        el.style.setProperty('background-color', 'transparent', 'important');
        el.style.setProperty('color', '#6F3D5D', 'important');
        var runs = el.querySelectorAll('*');
        for (var r = 0; r < runs.length; r++) {
          runs[r].style.setProperty('font-size', 'inherit', 'important');
          runs[r].style.setProperty('background', 'transparent', 'important');
          runs[r].style.setProperty('background-color', 'transparent', 'important');
          runs[r].style.setProperty('color', '#6F3D5D', 'important');
        }
      }
    }
  }

  function convertBoldside2BeforeBoldside2(paper) {
    var boldside2s = paper.querySelectorAll('.doc-p.boldside2, .word-boldside2');
    var bs1BasePx = 20;
    var fontDeltaPx = textStyle.font * 4 / 3;
    var lineTimes = textStyle.line;
    var newFontSize = bs1BasePx + fontDeltaPx;
    for (var i = 0; i < boldside2s.length; i++) {
      var el = boldside2s[i];
      var block = el.closest('.doc-block');
      if (!block) continue;
      var next = block.nextElementSibling;
      if (!next) continue;
      var nextIsBoldside2 = next.classList.contains('boldside2') ||
        (next.querySelector && next.querySelector('.boldside2'));
      if (nextIsBoldside2) {
        el.classList.remove('boldside2');
        el.classList.add('boldside1');
        if (block.classList.contains('boldside2')) {
          block.classList.remove('boldside2');
          block.classList.add('boldside1');
        }
        el.style.setProperty('font-size', newFontSize + 'px', 'important');
        block.style.setProperty('font-size', newFontSize + 'px', 'important');
        var baseLine = 13.5 * 4 / 3;
        el.style.setProperty('line-height', (newFontSize * 1.35 * lineTimes / 1.5) + 'px', 'important');
        el.style.setProperty('background', 'transparent', 'important');
        el.style.setProperty('background-color', 'transparent', 'important');
        el.style.setProperty('color', '#6F3D5D', 'important');
        var runs = el.querySelectorAll('*');
        for (var r = 0; r < runs.length; r++) {
          runs[r].style.setProperty('font-size', 'inherit', 'important');
          runs[r].style.setProperty('background', 'transparent', 'important');
          runs[r].style.setProperty('background-color', 'transparent', 'important');
          runs[r].style.setProperty('color', '#6F3D5D', 'important');
        }
      }
    }
  }

  // --- the face the note is set in ------------------------------------------
  // The faces belong to the app, not to the page, so Android sends both the
  // family to set and the @font-face blocks that reach the files it ships. The
  // rule has to be important: Word writes a font on every run, inline, and an
  // ordinary rule loses to that. An empty family leaves the note as written.
  var face = { family: '', css: '' };
  var headingFaces = {};
  var headingFaceCss = '';
  try {
    var seededFace = window.__CNL_TEXT_STYLE__;
    if (seededFace && typeof seededFace.face === 'string') {
      face.family = seededFace.face;
      face.css = typeof seededFace.faceCss === 'string' ? seededFace.faceCss : '';
    }
    if (seededFace && typeof seededFace.headings === 'object') {
      headingFaces = seededFace.headings;
    }
    if (seededFace && typeof seededFace.headingFaceCss === 'string') {
      headingFaceCss = seededFace.headingFaceCss;
    }
  } catch (error) {
    // No seed just means the note keeps its own fonts.
  }

  function applyFace() {
    var head = document.head || document.documentElement;
    if (!head) return;
    var style = document.querySelector('style[data-cnl-face]');
    if (!face.family && !headingFaceCss) {
      if (style && style.parentNode) style.parentNode.removeChild(style);
      return;
    }
    if (!style) {
      style = document.createElement('style');
      style.setAttribute('data-cnl-face', '');
      head.appendChild(style);
    }
    var css = face.css + headingFaceCss;
    // The body rule's seven :not() selectors push child specificity to (1,7,0,0).
    // Heading selectors can't use :not(.hN) — that would exclude the heading
    // element itself. Instead we repeat the ID (#paper#paper = specificity 2
    // for IDs) so heading rules land at (2,2,0,x) and beat the body rule.
    if (face.family) {
      css += '\n#paper, #paper *:not(.h1):not(.h2):not(.h3):not(.h4):not(.boldside1):not(.boldside2):not(.boldside3) { font-family: ' + face.family + ' !important; }\n';
      // Tables keep their own face whatever the body face is: the doubled ID
      // out-specifies the body rule above, which would otherwise reach into
      // every cell.
      css += '\n#paper#paper table, #paper#paper table * { font-family: "Source Sans Pro", sans-serif !important; }\n';
    }
    var headingMap = {
      h1: '#paper#paper .doc-p.h1, #paper#paper .doc-p.h1 *, #paper#paper .word-h1, #paper#paper .word-h1 *',
      h2: '#paper#paper .doc-p.h2, #paper#paper .doc-p.h2 *, #paper#paper .word-h2, #paper#paper .word-h2 *',
      h3: '#paper#paper .doc-p.h3, #paper#paper .doc-p.h3 *, #paper#paper .word-h3, #paper#paper .word-h3 *',
      h4: '#paper#paper .doc-p.h4, #paper#paper .doc-p.h4 *, #paper#paper .word-h4, #paper#paper .word-h4 *',
      bs1: '#paper#paper .doc-p.boldside1, #paper#paper .doc-p.boldside1 *, #paper#paper .word-boldside1, #paper#paper .word-boldside1 *',
      bs2: '#paper#paper .doc-p.boldside2, #paper#paper .doc-p.boldside2 *, #paper#paper .word-boldside2, #paper#paper .word-boldside2 *',
      bs3: '#paper#paper .doc-p.boldside3, #paper#paper .doc-p.boldside3 *, #paper#paper .word-boldside3, #paper#paper .word-boldside3 *'
    };
    for (var key in headingFaces) {
      if (headingFaces.hasOwnProperty(key) && headingMap[key]) {
        css += headingMap[key] + ' { font-family: "' + headingFaces[key] + '", serif !important; }\n';
      }
    }
    css += '#paper .cnl-glyph-calibri,\n' +
      '#paper .doc-list[data-list-level="1"] .list-marker.is-bullet::before {\n' +
      '  font-family: Calibri, Carlito, "Segoe UI Symbol", sans-serif !important;\n' +
      '}';
    style.textContent = css;
  }

  function armTextStyle() {
    var paper = document.getElementById('paper');
    if (!paper) return false;

    applyFace();

    // A new document replaces #paper's children wholesale, and those nodes have
    // no measured base yet, so every render needs one more pass. The same
    // render moves every heading, so the sitting heading is re-read with it.
    new MutationObserver(function () {
      // Drop the warm-tree skip so the new document is measured immediately.
      styledRoot = null;
      styledNodes = -1;
      styledScale = '';
      queueStyle();
      queueSittingHeading();
    }).observe(paper, { childList: true, subtree: true });
    sectionPaper(paper);
    stylePaper();
    styleTables();
    styleSections(paper);


    return true;
  }

  window.cnlTextStyle = function () {
    return JSON.stringify(textStyle);
  };

  window.cnlTextStyleSet = function (patchJson) {
    var patch = {};
    try { patch = JSON.parse(patchJson || '{}'); } catch (error) { patch = {}; }
    if (window.cnlReadingPresetSet) window.cnlReadingPresetSet(patch);
    styledRoot = null;
    if (typeof patch.font === 'number') textStyle.font = patch.font;
    if (typeof patch.line === 'number') textStyle.line = patch.line;
    if (typeof patch.para === 'number') textStyle.para = patch.para;
    var faceChanged = false;
    if (typeof patch.face === 'string') {
      face.family = patch.face;
      face.css = typeof patch.faceCss === 'string' ? patch.faceCss : '';
      faceChanged = true;
    }
    if (patch.headings && typeof patch.headings === 'object') {
      headingFaces = patch.headings;
      faceChanged = true;
    }
    if (typeof patch.headingFaceCss === 'string') {
      headingFaceCss = patch.headingFaceCss;
      faceChanged = true;
    }
    if (faceChanged) applyFace();
    saveTextStyle();
    var paper = document.getElementById('paper');
    if (paper) sectionPaper(paper);
    stylePaper();
    styleTables();
    if (paper) {
      styleSections(paper);


    }
    return JSON.stringify(textStyle);
  };

  // --- the heading the reader is sitting under -----------------------------
  // The page moves cnlCurrentHeadingIndex when a heading is tapped and never
  // while the note scrolls, so the bar would keep naming the heading the
  // reader left behind. The handoff follows the scroll instead: a heading
  // takes the bar once it has climbed into the upper third of the viewport,
  // and only once the heading before it has left the page, so two headings
  // on screen at once never fight over the bar. Writing the page's own index
  // is what carries the answer to Android, the outline and the read log.
  var HEADING_SELECTOR = '.doc-p.h1, .doc-p.h2, .doc-p.h3, .doc-p.h4';
  var HANDOFF_LINE = 0.3;
  // A leaving heading counts as gone a few pixels before its last line does,
  // which is also what a heading jump leaves of the one above its target.
  var GONE_EPS = 8;
  // A smooth scrollIntoView flies past every heading in between, so the
  // tracker stays quiet until the flight the page asked for has landed.
  var FLIGHT_MS = 900;

  var sittingQueued = false;
  var sittingLast = null;
  var sittingQuietUntil = 0;
  var firstGoneLast = null;
  var toolbarScrollPositions = new WeakMap();
  var toolbarScrollTravel = 0;
  var toolbarScrollDirection = 0;
  var toolbarFaded = false;

  function reportToolbarFade(faded) {
    if (faded === toolbarFaded) return;
    toolbarFaded = faded;
    var bridge = window.AndroidBridge;
    if (bridge && typeof bridge.onToolbarFadeChanged === 'function') {
      bridge.onToolbarFadeChanged(faded ? '1' : '0');
    }
  }

  function trackToolbarScroll(event) {
    if (viewOf(document.body) !== 'reader') return;
    var target = event.target;
    if (target === window || target === document) target = document.scrollingElement;
    if (!target || typeof target.scrollTop !== 'number') return;

    var position = target.scrollTop;
    var previous = toolbarScrollPositions.get(target);
    toolbarScrollPositions.set(target, position);
    if (previous == null) return;

    var delta = position - previous;
    if (!delta) return;
    var direction = delta > 0 ? 1 : -1;
    if (direction !== toolbarScrollDirection) {
      toolbarScrollDirection = direction;
      toolbarScrollTravel = 0;
    }
    toolbarScrollTravel += delta;

    var fadeTravel = 500 / (window.devicePixelRatio || 1);
    if (!toolbarFaded && toolbarScrollTravel >= fadeTravel) {
      toolbarScrollTravel = 0;
      reportToolbarFade(true);
    } else if (toolbarFaded && toolbarScrollTravel <= -fadeTravel) {
      toolbarScrollTravel = 0;
      reportToolbarFade(false);
    }
  }

  function shownHeadings() {
    var paper = document.getElementById('paper');
    if (!paper) return [];
    var all = paper.querySelectorAll(HEADING_SELECTOR);
    var shown = [];
    for (var i = 0; i < all.length; i++) {
      // The whole note stays on screen now, so every heading can vote for the bar.
      shown.push({ el: all[i], index: i });
    }
    return shown;
  }

  function sittingHeadingIndex() {
    var els = shownHeadings();
    if (!els.length) return null;

    var line = window.innerHeight * HANDOFF_LINE;
    var rects = [];
    var reached = -1;
    for (var i = 0; i < els.length; i++) {
      var rect = els[i].el.getBoundingClientRect();
      rects.push(rect);
      if (rect.top <= line) reached = i;
      else break;
    }

    // Walk back from the deepest heading that reached the line: it owns the
    // bar unless the one before it is still on the page, in which case that
    // one does, and so on up to a heading the viewport top has passed.
    for (var j = reached < 0 ? 0 : reached; j > 0; j--) {
      if (rects[j].top <= 0) return els[j].index;
      if (rects[j - 1].bottom <= GONE_EPS) return els[j].index;
    }
    return els[0].index;
  }

  /** True once the first heading on this sheet has left the top of the page. */
  function firstShownHeadingGone() {
    var els = shownHeadings();
    if (!els.length) return false;
    return els[0].el.getBoundingClientRect().bottom <= GONE_EPS;
  }

  function reportFirstHeadingGone(gone) {
    if (gone === firstGoneLast) return;
    firstGoneLast = gone;
    var bridge = window.AndroidBridge;
    if (bridge && typeof bridge.onFirstHeadingGone === 'function') {
      bridge.onFirstHeadingGone(gone ? '1' : '0');
    }
  }

  function reportSittingHeading() {
    sittingQueued = false;
    if (Date.now() < sittingQuietUntil) return;
    if (viewOf(document.body) !== 'reader') return;

    // A tap moved the index while the tracker was quiet: take up the thread
    // from where the page left it instead of writing the same value back.
    var current = window.cnlCurrentHeadingIndex;
    if (Number.isInteger(current) && current !== sittingLast) sittingLast = current;

    reportFirstHeadingGone(firstShownHeadingGone());

    var index = sittingHeadingIndex();
    if (index === null || index === sittingLast) return;
    sittingLast = index;
    console.info('[cnl] sitting ' + index);
    window.cnlCurrentHeadingIndex = index;
  }

  function queueSittingHeading() {
    if (sittingQueued) return;
    sittingQueued = true;
    requestAnimationFrame(reportSittingHeading);
  }

  window.cnlResetSittingTracker = function () {
    sittingLast = null;
    firstGoneLast = null;
    toolbarScrollPositions = new WeakMap();
    toolbarScrollTravel = 0;
    toolbarScrollDirection = 0;
    var scrollRoot = document.scrollingElement;
    if (scrollRoot) toolbarScrollPositions.set(scrollRoot, scrollRoot.scrollTop);
    reportToolbarFade(false);
    queueSittingHeading();
  };

  // 'scroll' does not bubble, so the listeners sit on every element the note
  // can scroll through, exactly as the page's own topbar tracker does.
  window.addEventListener('scroll', queueSittingHeading, { passive: true });
  document.addEventListener('scroll', queueSittingHeading, { passive: true, capture: true });
  window.addEventListener('scroll', trackToolbarScroll, { passive: true });
  document.addEventListener('scroll', trackToolbarScroll, { passive: true, capture: true });
  window.addEventListener('wheel', queueSittingHeading, { passive: true, capture: true });
  window.addEventListener('touchmove', queueSittingHeading, { passive: true, capture: true });
  window.addEventListener('resize', queueSittingHeading);

  var pageScrollIntoView = Element.prototype.scrollIntoView;
  Element.prototype.scrollIntoView = function (options) {
    if (options && typeof options === 'object' && options.behavior === 'smooth') {
      sittingQuietUntil = Date.now() + FLIGHT_MS;
      setTimeout(queueSittingHeading, FLIGHT_MS + 50);
    }
    return pageScrollIntoView.apply(this, arguments);
  };

  function armPage() {
    if (!viewWatched && document.body) {
      viewWatched = true;
      watchPage();
    }

    var armed = viewWatched;
    for (var i = 0; i < GRIDS.length; i++) {
      if (!GRIDS[i].armed) GRIDS[i].armed = armGrid(GRIDS[i]);
      armed = armed && GRIDS[i].armed;
    }
    if (!folderChooserWatched) folderChooserWatched = armFolderChooser();
    if (!textStyleWatched) textStyleWatched = armTextStyle();
    return armed && folderChooserWatched && textStyleWatched;
  }

  function armPageWithRetries(attempt) {
    if (armPage() || attempt >= ARM_ATTEMPTS) return;
    setTimeout(function () { armPageWithRetries(attempt + 1); }, ARM_DELAY_MS);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () { armPageWithRetries(0); });
  } else {
    armPageWithRetries(0);
  }

  HTMLAnchorElement.prototype.click = function () {
    var fileName = this.getAttribute('download');
    var href = this.getAttribute('href') || this.href || '';

    if (fileName && href.indexOf('blob:') === 0) {
      handOff(href, fileName);
      return;
    }
    return nativeClick.apply(this, arguments);
  };

  // One provider per tool. The page's own patch entry re-points every tool at
  // once, so a single tool's provider is written through its own store; a model
  // name belongs to one provider, so the old one goes with the change. The
  // page's readers and writers for that store live inside its own closure, so
  // the bridge speaks to the store directly, under the page's key.
  var AI_TASK_STORE = 'cnlAiTaskModelSettingsV1';

  window.cnlAiTaskSet = function (kind, provider) {
    var configs = {};
    try { configs = JSON.parse(localStorage.getItem(AI_TASK_STORE) || '{}') || {}; } catch (error) { configs = {}; }
    var entry = configs[kind] || (configs[kind] = {});
    entry.provider = provider;
    delete entry.model;
    localStorage.setItem(AI_TASK_STORE, JSON.stringify(configs));
    return window.cnlAiSettings();
  };
})();

