import Foundation

/// Runs page actions through JavaScript. Elements are addressed by the number from WebPageAnalyzer.
/// Every script returns a string, because a nil result from WebKit must never reach Swift.
@MainActor
struct WebActionRunner {
    let store: WebViewStore

    func click(index: Int) async -> Bool {
        let script = "(function(){var el=document.querySelector('[data-sa-index=\"\(index)\"]');if(!el){return 'missing';}el.click();return 'ok';})();"
        let result = await store.evaluate(script) as? String
        return result == "ok"
    }

    func scroll(down: Bool) async {
        let direction = down ? 1 : -1
        _ = await store.evaluate("(function(){window.scrollBy(0, \(direction) * window.innerHeight * 0.8);return 'ok';})();")
    }

    /// Scrolls to the next heading below the current view and returns its text.
    func nextHeading() async -> String? {
        let script = """
        (function(){var hs=Array.prototype.slice.call(document.querySelectorAll('h1, h2, h3'));var h=hs.find(function(x){return x.getBoundingClientRect().top > 8;});if(!h){return '';}h.scrollIntoView({block:'start'});return (h.innerText||'').trim();})();
        """
        let text = await store.evaluate(script) as? String ?? ""
        return text.isEmpty ? nil : text
    }

    /// Sets a field's value and fires the input events that frameworks listen for.
    func type(_ value: String, index: Int) async -> Bool {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: " ")
        let script = """
        (function(){var el=document.querySelector('[data-sa-index="\(index)"]');if(!el){return 'missing';}\
        if(el.type==='password'){return 'refused';}el.focus();\
        if(el.tagName==='SELECT'){var o=Array.prototype.find.call(el.options,function(x){return x.text.toLowerCase().indexOf('\(escaped)'.toLowerCase())>=0;});if(!o){return 'missing';}el.value=o.value;}\
        else{el.value='\(escaped)';}\
        el.setAttribute('data-sa-touched','1');\
        el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));return 'ok';})();
        """
        let result = await store.evaluate(script) as? String
        return result == "ok"
    }

    /// Submits the form the user has been filling in; otherwise the form with the most fields.
    /// Uses requestSubmit so the page's own validation and handlers run.
    func submitForm() async -> Bool {
        let script = """
        (function(){var touched=document.querySelector('[data-sa-touched]');var f=touched?touched.closest('form'):null;\
        if(!f){var forms=Array.prototype.slice.call(document.querySelectorAll('form'));forms.sort(function(a,b){return b.querySelectorAll('input,select,textarea').length-a.querySelectorAll('input,select,textarea').length;});f=forms[0];}\
        if(!f){return 'missing';}if(f.requestSubmit){f.requestSubmit();}else{f.submit();}return 'ok';})();
        """
        let result = await store.evaluate(script) as? String
        return result == "ok"
    }
}
