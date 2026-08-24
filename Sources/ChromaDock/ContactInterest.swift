import Foundation

enum ContactInterest: Sendable {
    static let subject = "ChromaDock Interest"
    static let defaultBody = "I'd like to hear when paid custom separators are available for ChromaDock."
    static let widgetID = "9348b19c-e100-4b57-87f3-917139bec823"
    static let pageURL = URL(string: "https://nextcz.com/#\(widgetID)")!

    static func message(body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = trimmed.isEmpty ? defaultBody : trimmed
        if text == subject || text.hasPrefix(subject + "\n") {
            return text
        }
        return "\(subject)\n\n\(text)"
    }

    static func prefillJavaScript(message: String) -> String {
        let encodedMessage = jsonStringLiteral(message)
        let encodedWidgetID = jsonStringLiteral(widgetID)
        return """
        (function() {
          const message = \(encodedMessage);
          const widgetId = \(encodedWidgetID);
          let focused = false;

          function setNativeValue(el, value) {
            const proto = el.tagName === 'TEXTAREA'
              ? window.HTMLTextAreaElement.prototype
              : window.HTMLInputElement.prototype;
            const desc = Object.getOwnPropertyDescriptor(proto, 'value');
            const tracker = el._valueTracker;
            if (tracker && typeof tracker.setValue === 'function') tracker.setValue('');
            if (desc && desc.set) desc.set.call(el, value);
            else el.value = value;
            el.dispatchEvent(new Event('input', { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
            const propsKey = Object.keys(el).find(function(k) {
              return k.indexOf('__reactProps$') === 0 || k.indexOf('__reactEventHandlers$') === 0;
            });
            if (propsKey && el[propsKey] && typeof el[propsKey].onChange === 'function') {
              try {
                el[propsKey].onChange({
                  target: el,
                  currentTarget: el,
                  preventDefault: function() {},
                  persist: function() {}
                });
              } catch (e) {}
            }
          }

          function fill() {
            const widget = document.getElementById(widgetId)
              || document.querySelector('[data-aid="CONTACT_FORM_CONTAINER_REND"]');
            if (widget && widget.scrollIntoView) {
              try { widget.scrollIntoView({ behavior: 'smooth', block: 'center' }); }
              catch (e) { widget.scrollIntoView(); }
            }
            const ta = document.querySelector('textarea[data-aid="CONTACT_FORM_MESSAGE"]')
              || document.querySelector('[data-aid="CONTACT_FORM_MESSAGE"]');
            if (!ta) return false;
            const current = (ta.value || '').trim();
            if (!current) setNativeValue(ta, message);
            const email = document.querySelector('input[data-aid="CONTACT_FORM_EMAIL"]')
              || document.querySelector('[data-aid="CONTACT_FORM_EMAIL"]');
            if (email && email.focus && !focused) {
              email.focus();
              focused = true;
            }
            return true;
          }

          fill();
          const root = document.documentElement || document.body;
          const obs = new MutationObserver(function() { fill(); });
          if (root) obs.observe(root, { childList: true, subtree: true });
          let n = 0;
          const t = setInterval(function() {
            n += 1;
            fill();
            if (n > 40) {
              clearInterval(t);
              obs.disconnect();
            }
          }, 250);
        })();
        """
    }

    static func jsonStringLiteral(_ string: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [string])
        let wrapped = String(data: data, encoding: .utf8)!
        return String(wrapped.dropFirst().dropLast())
    }
}
