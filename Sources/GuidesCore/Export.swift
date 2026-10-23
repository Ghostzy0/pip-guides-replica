import AppKit
import CoreText

public enum GuideExport {
    public static func htmlEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;")
    }
    public static func html(_ document: GuideDocument) throws -> String {
        try document.validate()
        let steps = try document.steps.enumerated().map { index, step -> String in
            let stepNumber = document.steps.prefix(index + 1).filter { $0.kind == .step }.count
            let imageLabel = step.kind == .step ? "Screenshot for step \(stepNumber)" : "\(step.kind.title) image"
            let image = try step.image.map { "<img alt=\"\(htmlEscape(imageLabel))\" src=\"data:image/png;base64,\(try ImageTools.marked($0, at: step.click).base64EncodedString())\">" } ?? ""
            let label = step.kind == .step ? "\(stepNumber). \(htmlEscape(step.title))" : "\(step.kind.title) · \(htmlEscape(step.title))"
            return "<section class=\"\(step.kind.rawValue)\"><h\(step.kind == .header ? 2 : 3)>\(label)</h\(step.kind == .header ? 2 : 3)><p>\(htmlEscape(step.body))</p>\(image)</section>"
        }.joined(separator: "\n")
        return """
        <!doctype html><html lang="en-GB"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'">
        <title>\(htmlEscape(document.title))</title><style>body{font:17px/1.6 system-ui,sans-serif;color:#121211;background:white;max-width:860px;margin:48px auto;padding:0 24px;overflow-wrap:anywhere}h1{font-size:34px;line-height:1.2}h2{font-size:23px}h3{font-size:20px}p{white-space:pre-wrap}section{margin:36px 0;break-inside:avoid}section.tip,section.alert{padding:18px 22px;border-left:4px solid #777;background:#f5f5f5}section.header{margin-top:44px}img{display:block;max-width:100%;height:auto;border:1px solid #dedede;border-radius:12px}footer{color:#555;border-top:1px solid #dedede;padding-top:20px}@media print{body{margin:0}section{break-inside:auto}}</style>
        <main><h1>\(htmlEscape(document.title))</h1><p>\(htmlEscape(document.summary))</p>\(steps)</main><footer>Created with Pip Guides · Local guide</footer></html>
        """
    }
    public static func markdown(_ document: GuideDocument) throws -> String {
        try document.validate()
        // HTML text elements prevent untrusted Markdown/HTML from becoming active links or markup.
        // Embedded data images keep this file self-contained. Some Markdown viewers block data URLs.
        var out = "# \(markdownText(document.title))\n\n<p>\(htmlEscape(document.summary))</p>\n"
        for (index, step) in document.steps.enumerated() {
            let stepNumber = document.steps.prefix(index + 1).filter { $0.kind == .step }.count
            let prefix = step.kind == .step ? "\(stepNumber). " : "\(step.kind.title) · "
            out += "\n## \(prefix)\(markdownText(step.title))\n\n<p>\(htmlEscape(step.body).replacingOccurrences(of: "\n", with: "<br>"))</p>\n"
            if let image = step.image { out += "\n![\(step.kind == .step ? "Step \(stepNumber)" : step.kind.title)](data:image/png;base64,\(try ImageTools.marked(image, at: step.click).base64EncodedString()))\n" }
        }
        return out
    }
    private static func markdownText(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\n", with: " ").reduce(into: "") { result, c in
            if "\\`*_{}[]()#+-.!|".contains(c) { result.append("\\") }; result.append(c)
        }
        return htmlEscape(escaped)
    }
    public static func pdf(_ document: GuideDocument) throws -> Data {
        try document.validate()
        let output = NSMutableData()
        var page = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let consumer = CGDataConsumer(data: output as CFMutableData), let ctx = CGContext(consumer: consumer, mediaBox: &page, nil) else { throw GuideError.invalidDocument }
        func drawText(_ string: String, size: CGFloat, rect: CGRect, start: Int = 0) -> Int {
            let style = NSMutableParagraphStyle(); style.lineSpacing = 4
            let attr = NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.black, .paragraphStyle: style])
            let setter = CTFramesetterCreateWithAttributedString(attr)
            let path = CGPath(rect: rect, transform: nil)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: start, length: 0), path, nil)
            CTFrameDraw(frame, ctx); return CTFrameGetVisibleStringRange(frame).length
        }
        let intro = document.title + "\n\n" + document.summary
        var offset = 0
        repeat {
            ctx.beginPDFPage(nil)
            let count = drawText(intro, size: offset == 0 ? 22 : 16, rect: CGRect(x: 48, y: 65, width: 499, height: 720), start: offset)
            offset += count; ctx.endPDFPage()
            if count == 0 { break }
        } while offset < (intro as NSString).length
        for (index, step) in document.steps.enumerated() {
            ctx.beginPDFPage(nil)
            let stepNumber = document.steps.prefix(index + 1).filter { $0.kind == .step }.count
            let title = step.kind == .step ? "Step \(stepNumber)" : step.kind.title
            let content = step.title + "\n\n" + step.body
            _ = drawText(title, size: 20, rect: CGRect(x: 48, y: 715, width: 499, height: 80))
            var bottom: CGFloat = 65, height: CGFloat = 625
            if let data = step.image {
                let image = try ImageTools.cgImage(ImageTools.marked(data, at: step.click))
                let scale = min(499 / CGFloat(image.width), 340 / CGFloat(image.height))
                let imageHeight = CGFloat(image.height) * scale
                ctx.draw(image, in: CGRect(x: 48, y: 690-imageHeight, width: CGFloat(image.width)*scale, height: imageHeight))
                height = 690-imageHeight-24-bottom
            }
            offset = 0
            var count = drawText(content, size: 15, rect: CGRect(x: 48, y: bottom, width: 499, height: height))
            offset += count; ctx.endPDFPage()
            while offset < (content as NSString).length && count > 0 {
                ctx.beginPDFPage(nil); bottom = 65
                count = drawText(content, size: 15, rect: CGRect(x: 48, y: bottom, width: 499, height: 720), start: offset)
                offset += count; ctx.endPDFPage()
            }
        }
        ctx.closePDF(); return output as Data
    }
}
