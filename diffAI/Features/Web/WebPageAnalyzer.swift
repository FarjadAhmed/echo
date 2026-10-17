import Foundation

/// Reads a page's structure with JavaScript. Interactive elements get a number (data-sa-index)
/// so later actions can target them, for example "click number 4".
/// Password values are never collected; other field values are kept short and stay on the device.
enum WebPageAnalyzer {
    static let script = #"""
    (function () {
      function clean(s) { return (s || '').replace(/\s+/g, ' ').trim(); }
      function visible(el) {
        if (el.closest('[aria-hidden="true"]')) { return false; }
        var r = el.getBoundingClientRect();
        var st = window.getComputedStyle(el);
        return r.width > 0 && r.height > 0 && st.visibility !== 'hidden' && st.display !== 'none' && st.opacity !== '0';
      }
      function labelFor(el) {
        var lab = (el.labels && el.labels.length) ? clean(el.labels[0].innerText) : '';
        var valueLabel = (el.type === 'submit' || el.type === 'button') ? el.value : '';
        var img = el.querySelector && el.querySelector('img[alt]');
        var alt = img ? img.getAttribute('alt') : '';
        var text = clean(el.getAttribute('aria-label') || lab || el.innerText || valueLabel || el.placeholder || el.title || alt || el.name || el.id || '');
        return text.length > 80 ? text.slice(0, 77) + '...' : text;
      }
      var index = 0;
      var elements = [];
      var nodes = document.querySelectorAll('a[href], button, input:not([type=hidden]), select, textarea, [role=button]');
      Array.prototype.forEach.call(nodes, function (el) {
        if (!visible(el)) { return; }
        index += 1;
        el.setAttribute('data-sa-index', String(index));
        if (elements.length >= 80) { return; }
        var tag = el.tagName;
        var kind = tag === 'A' ? 'link'
          : ((tag === 'BUTTON' || el.getAttribute('role') === 'button' || el.type === 'submit' || el.type === 'button') ? 'button' : 'field');
        var type = (el.type || tag).toLowerCase();
        var inForm = !!el.closest('form');
        elements.push({
          index: index,
          kind: kind,
          label: labelFor(el) || '(no label)',
          type: type,
          value: (kind === 'field' && type !== 'password') ? clean(el.value).slice(0, 60) : '',
          href: tag === 'A' ? (el.href || '') : '',
          inForm: inForm
        });
      });
      function texts(selector, limit) {
        return Array.prototype.map.call(document.querySelectorAll(selector), function (h) {
          return clean(h.innerText);
        }).filter(function (t) { return t.length > 0; }).slice(0, limit);
      }
      var landmarks = Array.prototype.map.call(
        document.querySelectorAll('header, nav, main, footer, [role=main], [role=navigation], [role=search]'),
        function (e) { return clean(e.getAttribute('aria-label') || e.tagName.toLowerCase()); }
      ).slice(0, 20);
      var main = document.querySelector('main') || document.querySelector('article') || document.body;
      // Keep line breaks so the reader can split the text into sentences and paragraphs.
      var lines = (main.innerText || '').split('\n').map(clean).filter(function (t) { return t.length > 0; });
      var mainText = lines.join('\n');
      if (mainText.length > 8000) { mainText = mainText.slice(0, 8000); mainText = mainText.slice(0, mainText.lastIndexOf(' ')); }
      return JSON.stringify({
        title: clean(document.title),
        url: location.href,
        headings: texts('h1, h2, h3', 30),
        landmarks: landmarks,
        elements: elements,
        mainText: mainText,
        formCount: document.querySelectorAll('form').length,
        hasPasswordField: !!document.querySelector('input[type=password]')
      });
    })();
    """#
}
