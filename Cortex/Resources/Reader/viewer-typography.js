/* Align bullets to the visible first-line text, independent of extra leading. */
(function () {
  'use strict';
  var canvas = document.createElement('canvas');
  var context = canvas.getContext('2d');
  var offsets = Object.create(null);
  var headingSelector = '.doc-p.h4,.doc-p.boldside1,.doc-p.boldside2,.doc-p.boldside3,' +
    '.word-h4,.word-boldside1,.word-boldside2,.word-boldside3,.section-head,.group-h';

  function restoreProperty(element, name, value, priority) {
    if (value) element.style.setProperty(name, value, priority);
    else element.style.removeProperty(name);
  }

  window.cnlClearHeadingIndents = function (root) {
    var headings = (root || document).querySelectorAll(headingSelector);
    for (var i = 0; i < headings.length; i++) {
      var element = headings[i], saved = element.__cnlHeadingIndent;
      if (!saved) continue;
      restoreProperty(element, 'padding-left', saved.padding, saved.paddingPriority);
      restoreProperty(element, 'text-indent', saved.indent, saved.indentPriority);
      delete element.__cnlHeadingIndent;
    }
  };

  // Keep the first line at its original start; subsequent lines inset by 4px.
  window.cnlIndentHeadingPrefixes = function (root) {
    root = root || document;
    window.cnlClearHeadingIndents(root);
    var headings = root.querySelectorAll(headingSelector), layouts = [];
    for (var i = 0; i < headings.length; i++) {
      var element = headings[i];
      if (element.closest('table') || element.parentElement.closest(headingSelector)) continue;
      var marker = element.querySelector(':scope > .list-marker');
      if (marker) {
        if (!marker.classList.contains('is-number') ||
            !/^[ \t\u00a0]*(?:[a-zA-Z]{1,2}|[ivxlcdmIVXLCDM]+|\d+(?:\.\d+)*)[.)][ \t\u00a0]*$/.test(marker.textContent)) continue;
      } else if (!/^[ \t\u00a0]*(?:[a-zA-Z]{1,2}|[ivxlcdmIVXLCDM]+|\d+(?:\.\d+)*)[.)][ \t\u00a0]+(?=\S)/.test(element.textContent)) continue;
      var style = getComputedStyle(element);
      layouts.push({element: element, inset: parseFloat(style.paddingLeft) || 0});
    }
    // Read all original insets before applying padding.
    for (var j = 0; j < layouts.length; j++) {
      var layout = layouts[j], element = layout.element;
      element.__cnlHeadingIndent = {
        padding: element.style.getPropertyValue('padding-left'),
        paddingPriority: element.style.getPropertyPriority('padding-left'),
        indent: element.style.getPropertyValue('text-indent'),
        indentPriority: element.style.getPropertyPriority('text-indent')
      };
      element.style.setProperty('padding-left', (layout.inset + 4) + 'px', 'important');
      element.style.setProperty('text-indent', '-4px', 'important');
    }
  };

  function textMidlineOffset(style) {
    var font = style.fontStyle + ' ' + style.fontWeight + ' ' + style.fontSize + ' ' + style.fontFamily;
    var key = font + '|' + style.lineHeight;
    if (offsets[key] !== undefined) return offsets[key];
    if (!context) return 0;
    context.font = font;
    // Aa represents the capital and lowercase ink, without descender skew.
    var metrics = context.measureText('Aa');
    var inkAscent = metrics.actualBoundingBoxAscent;
    var inkDescent = metrics.actualBoundingBoxDescent;
    // Measure the browser's actual baseline: rounding of font ascender metrics
    // can differ from Canvas by half a pixel, especially at small body sizes.
    var probe = document.createElement('span');
    probe.style.cssText = 'position:fixed;left:-10000px;top:0;visibility:hidden;display:block;padding:0;margin:0;white-space:nowrap';
    probe.style.font = font;
    probe.style.lineHeight = style.lineHeight;
    probe.appendChild(document.createTextNode('Aa'));
    var baseline = document.createElement('i');
    baseline.style.cssText = 'display:inline-block;width:0;height:0;padding:0;margin:0;vertical-align:baseline';
    probe.appendChild(baseline);
    document.body.appendChild(probe);
    var rect = probe.getBoundingClientRect();
    var offset = [inkAscent, inkDescent].every(Number.isFinite)
      ? baseline.getBoundingClientRect().top - rect.top - rect.height / 2
        - (inkAscent - inkDescent) / 2 : 0;
    probe.remove();
    offsets[key] = offset;
    return offset;
  }

  window.cnlAlignBulletMarkers = function (root) {
    root = root || document;
    var rows = root.querySelectorAll('.doc-list:has(> .list-marker.is-bullet), li.doc-li');
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i];
      var content = row.querySelector(':scope > .list-content') || row;
      var style = getComputedStyle(content);
      row.style.setProperty('--cnl-marker-midline-offset', textMidlineOffset(style) + 'px');
      if (content !== row) row.style.setProperty('--cnl-list-first-line-height', style.lineHeight);
      else {
        var marker = getComputedStyle(row, '::before');
        var top = parseFloat(style.paddingTop) + parseFloat(style.lineHeight) / 2
          + textMidlineOffset(style) - parseFloat(marker.height) / 2;
        row.style.setProperty('--cnl-marker-top', top + 'px');
      }
    }
  };

  function ready() {
    window.cnlIndentHeadingPrefixes();
    window.cnlAlignBulletMarkers();
    if (document.fonts) {
      function fontsReady() {
        offsets = Object.create(null);
        window.cnlIndentHeadingPrefixes();
        window.cnlAlignBulletMarkers();
      }
      document.fonts.ready.then(fontsReady);
      document.fonts.addEventListener('loadingdone', fontsReady);
    }
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', ready);
  else ready();
})();
