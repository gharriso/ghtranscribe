import SwiftUI
import WebKit

struct HTMLView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let styled = """
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        body {
            font-family: -apple-system, sans-serif;
            font-size: 16px;
            line-height: 1.4;
            padding: 16px;
            margin: 0;
            color: -apple-system-label;
        }
        table { border-collapse: collapse; width: 100%; margin-bottom: 12px; }
        td, th { border: 1px solid #ccc; padding: 6px; text-align: left; vertical-align: top; }
        h2 { font-size: 1.1em; }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
        webView.loadHTMLString(styled, baseURL: nil)
    }
}
