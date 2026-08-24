import SwiftUI
import WebKit

struct ContactInterestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var bodyText = ContactInterest.defaultBody
    @State private var showForm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showForm {
                Text("Add your email and send. The message is already filled in and can still be edited on the form.")
                    .foregroundStyle(.secondary)
                ContactFormWebView(message: ContactInterest.message(body: bodyText))
                    .frame(minWidth: 680, minHeight: 520)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.separator, lineWidth: 1)
                    )
            } else {
                Text("Coming soon in paid version")
                    .font(.title2.weight(.semibold))
                Text("Custom separators will ship in the paid version. Register interest with the same nextcz.com contact form other inquiries use — GoDaddy Conversations, optional email list, and reCAPTCHA.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Subject")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(ContactInterest.subject)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Message")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $bodyText)
                        .font(.body)
                        .frame(minHeight: 120)
                        .padding(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(.separator, lineWidth: 1)
                        )
                        .accessibilityLabel("Interest message")
                }
                Text("The form only asks for email after this. Name and the email-list checkbox stay yours to fill in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                if showForm {
                    Button("Back") { showForm = false }
                    Spacer()
                    Button("Close") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                } else {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Open nextcz.com contact form") { showForm = true }
                        .buttonStyle(.link)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityLabel("Open nextcz.com contact form")
                }
            }
        }
        .padding(20)
        .frame(minWidth: showForm ? 720 : 520, minHeight: showForm ? 640 : 420)
    }
}

struct ContactFormWebView: NSViewRepresentable {
    let message: String

    func makeCoordinator() -> Coordinator {
        Coordinator(message: message)
    }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: ContactInterest.pageURL))
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.message = message
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var message: String

        init(message: String) {
            self.message = message
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            inject(into: webView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak webView] in
                guard let webView else { return }
                self.inject(into: webView)
            }
        }

        private func inject(into webView: WKWebView) {
            webView.evaluateJavaScript(ContactInterest.prefillJavaScript(message: message), completionHandler: nil)
        }
    }
}
