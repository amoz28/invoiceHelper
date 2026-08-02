import Foundation
import PDFKit
import UIKit

/// Builds an A4 invoice PDF matching the layout and content of React Native `src/utils/pdfGenerator.ts`
/// (letterhead, bill-to / invoice meta, line table, totals, payments, notes/terms, bank footer).
enum InvoicePDFGenerator {

    private static let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4, points
    private static let margin: CGFloat = 36
    private static let contentWidth = pageRect.width - margin * 2
    private static let bodyColor = UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)
    private static let lightGray = UIColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1)
    private static let tableHeaderGray = UIColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1)
    private static let borderGray = UIColor(red: 0.87, green: 0.87, blue: 0.87, alpha: 1)

    private static let gbDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "dd MMM yyyy"
        return f
    }()

    static func generatePDFData(invoice: Invoice, company: CompanyProfile, customer: Customer) async -> Data {
        let logoImage = await loadLogoImage(from: company.logo)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        var linkAnnotations: [(page: Int, rect: CGRect, url: URL)] = []
        let data = renderer.pdfData { ctx in
            var layout = Layout(ctx: ctx, pageRect: pageRect, margin: margin)
            layout.beginPage()

            let sym = InvoiceLogic.currencySymbol(for: company.currency)
            let payments = invoice.payments ?? []
            let totalPaid = payments.reduce(0) { $0 + $1.amount }
            let remaining = invoice.total - totalPaid

            drawLetterhead(&layout, company: company, logo: logoImage)
            layout.y += 8

            layout.drawCentered("INVOICE", font: .boldSystemFont(ofSize: 28), color: bodyColor)
            layout.y += 18

            drawBillingSection(&layout, invoice: invoice, customer: customer, sym: sym)
            layout.y += 14

            drawItemsTable(&layout, invoice: invoice, sym: sym)
            layout.y += 10

            drawTotals(&layout, invoice: invoice, sym: sym, totalPaid: totalPaid, remaining: remaining, hasPayments: !payments.isEmpty)
            layout.y += 12

            if !payments.isEmpty {
                drawPaymentHistory(&layout, payments: payments, sym: sym)
                layout.y += 12
            }

            if let notes = invoice.notes, !notes.isEmpty {
                layout.ensureSpace(80)
                drawNotesBox(&layout, title: "Notes:", body: notes, accent: UIColor(red: 0.13, green: 0.59, blue: 0.95, alpha: 1))
                layout.y += 10
            }

            if let terms = invoice.terms, !terms.isEmpty {
                layout.ensureSpace(80)
                drawNotesBox(&layout, title: "Terms & Conditions:", body: terms, accent: UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1), fontSize: 11)
                layout.y += 10
            }

            layout.ensureSpace(100)
            drawBankFooter(&layout, company: company)
            drawPaymentLinkFooter(&layout, company: company)
            linkAnnotations = layout.linkAnnotations
        }
        return embedLinkAnnotations(in: data, links: linkAnnotations)
    }

    /// Normalizes optional payment URL for PDF link annotations (https default).
    static func normalizedPaymentURL(_ raw: String?) -> URL? {
        let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !s.isEmpty else { return nil }
        if let u = URL(string: s), let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return u
        }
        let prefixed = s.hasPrefix("//") ? "https:\(s)" : "https://\(s)"
        return URL(string: prefixed)
    }

    private static func embedLinkAnnotations(in data: Data, links: [(page: Int, rect: CGRect, url: URL)]) -> Data {
        guard !links.isEmpty, let doc = PDFDocument(data: data) else { return data }
        for link in links {
            guard let page = doc.page(at: link.page) else { continue }
            let media = page.bounds(for: .mediaBox)
            let H = media.height
            let r = link.rect
            let pdfRect = CGRect(x: r.minX, y: H - r.maxY, width: r.width, height: r.height)
            let ann = PDFAnnotation(bounds: pdfRect, forType: .link, withProperties: nil)
            ann.url = link.url
            page.addAnnotation(ann)
        }
        return doc.dataRepresentation() ?? data
    }

    private static func drawPaymentLinkFooter(_ layout: inout Layout, company: CompanyProfile) {
        guard let url = normalizedPaymentURL(company.paymentLink) else { return }
        let host = url.host ?? url.absoluteString
        let text = "Pay online: \(host)"
        let font = UIFont.systemFont(ofSize: 12)
        let attr: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.systemBlue,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        let str = NSAttributedString(string: text, attributes: attr)
        let size = str.size()
        let maxW = contentWidth - 24
        let w = min(ceil(size.width), maxW)
        let h = ceil(size.height)
        layout.ensureSpace(h + 12)
        let y = layout.y
        let x = layout.pageRect.midX - w / 2
        str.draw(with: CGRect(x: x, y: y, width: w, height: h), options: [.usesLineFragmentOrigin], context: nil)
        layout.linkAnnotations.append((page: layout.pageIndex, rect: CGRect(x: x, y: y, width: w, height: h), url: url))
        layout.y += h + 8
    }

    // MARK: - Sections

    private static func drawLetterhead(_ layout: inout Layout, company: CompanyProfile, logo: UIImage?) {
        if let img = logo {
            let maxW: CGFloat = 120
            let maxH: CGFloat = 60
            let scale = min(maxW / img.size.width, maxH / img.size.height, 1)
            let w = img.size.width * scale
            let h = img.size.height * scale
            let x = layout.pageRect.midX - w / 2
            img.draw(in: CGRect(x: x, y: layout.y, width: w, height: h))
            layout.y += h + 8
        }

        layout.drawCentered(company.name, font: .boldSystemFont(ofSize: 20), color: bodyColor)
        layout.y += 8

        let addr = "Address: \(company.billingAddress.street), \(company.billingAddress.city), \(company.billingAddress.state) \(company.billingAddress.postalCode), \(company.billingAddress.country)"
        layout.drawCenteredParagraph(addr, font: .systemFont(ofSize: 12), color: bodyColor, spacing: 4)

        var contact = ""
        if !company.phone.isEmpty { contact += "Phone: \(company.phone)" }
        if !company.phone.isEmpty, !company.email.isEmpty { contact += " | " }
        if !company.email.isEmpty { contact += "Email: \(company.email)" }
        if !contact.isEmpty {
            layout.drawCenteredParagraph(contact, font: .systemFont(ofSize: 12), color: bodyColor, spacing: 4)
        }

        layout.y += 6
        let lineY = layout.y
        layout.cgContext.setStrokeColor(UIColor.darkGray.cgColor)
        layout.cgContext.setLineWidth(2)
        layout.cgContext.move(to: CGPoint(x: margin, y: lineY))
        layout.cgContext.addLine(to: CGPoint(x: pageRect.width - margin, y: lineY))
        layout.cgContext.strokePath()
        layout.y = lineY + 12
    }

    private static func drawBillingSection(_ layout: inout Layout, invoice: Invoice, customer: Customer, sym: String) {
        let colGap: CGFloat = 20
        let half = (contentWidth - colGap) / 2
        let leftX = margin
        let rightX = margin + half + colGap
        var leftY = layout.y
        var rightY = layout.y

        let billToTitle = sectionTitleAttributes()
        NSAttributedString(string: "Bill To:", attributes: billToTitle).draw(at: CGPoint(x: leftX, y: leftY))
        leftY += 18

        let custName = customer.name.isEmpty ? (customer.displayName ?? "") : customer.name
        NSAttributedString(string: custName, attributes: boldBodyAttributes(size: 13)).draw(at: CGPoint(x: leftX, y: leftY))
        leftY += 16
        for line in [
            customer.billingAddress.street,
            "\(customer.billingAddress.city), \(customer.billingAddress.state) \(customer.billingAddress.postalCode)",
            customer.billingAddress.country,
        ] {
            NSAttributedString(string: line, attributes: bodyAttributes(size: 12)).draw(at: CGPoint(x: leftX, y: leftY))
            leftY += 14
        }

        let invTitle = NSMutableAttributedString(string: "Invoice Details:", attributes: sectionTitleAttributes())
        let titleSize = invTitle.size()
        invTitle.draw(at: CGPoint(x: rightX + half - titleSize.width, y: rightY))
        rightY += 18

        func drawRightRow(label: String, value: String) {
            let lab = NSAttributedString(string: label, attributes: boldBodyAttributes(size: 12))
            let val = NSAttributedString(string: value, attributes: bodyAttributes(size: 12))
            let vw = val.size().width
            let lw = lab.size().width
            val.draw(at: CGPoint(x: rightX + half - vw, y: rightY))
            lab.draw(at: CGPoint(x: rightX + half - vw - lw - 8, y: rightY))
            rightY += 14
        }

        drawRightRow(label: "Invoice #:", value: invoice.invoiceNumber)
        drawRightRow(label: "Date:", value: formatDate(iso: invoice.date))
        drawRightRow(label: "Due Date:", value: formatDate(iso: invoice.dueDate))

        layout.y = max(leftY, rightY)
    }

    private static func drawItemsTable(_ layout: inout Layout, invoice: Invoice, sym: String) {
        // Wider description column; qty / unit / amount slightly narrower.
        let widths: [CGFloat] = [contentWidth * 0.58, contentWidth * 0.14, contentWidth * 0.14, contentWidth * 0.14]
        let headers = ["Description", "Quantity", "Unit Price", "Amount"]
        let headerH: CGFloat = 24

        var estimatedBody: CGFloat = 0
        for item in invoice.items {
            let descW = widths[0] - 16
            let ps = NSMutableParagraphStyle()
            ps.alignment = .left
            let descAttr = NSAttributedString(
                string: item.description,
                attributes: [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: bodyColor, .paragraphStyle: ps]
            )
            let h = descAttr.boundingRect(with: CGSize(width: descW, height: 10_000), options: [.usesLineFragmentOrigin], context: nil).height
            estimatedBody += max(ceil(h) + 8, 22)
        }

        layout.ensureSpace(headerH + estimatedBody + 8)

        var x = margin
        let ctx = layout.cgContext
        ctx.setFillColor(tableHeaderGray.cgColor)
        ctx.fill(CGRect(x: margin, y: layout.y, width: contentWidth, height: headerH))

        for (i, h) in headers.enumerated() {
            let w = widths[i]
            let attr = boldBodyAttributes(size: 12)
            let str = NSAttributedString(string: h, attributes: attr)
            let drawX: CGFloat = i == 0 ? x + 8 : x + w - str.size().width - 8
            str.draw(at: CGPoint(x: drawX, y: layout.y + 6))
            x += w
        }

        ctx.setStrokeColor(borderGray.cgColor)
        ctx.setLineWidth(0.5)
        ctx.stroke(CGRect(x: margin, y: layout.y, width: contentWidth, height: headerH))

        layout.y += headerH

        for item in invoice.items {
            x = margin
            let descW = widths[0] - 16
            let ps = NSMutableParagraphStyle()
            ps.alignment = .left
            let descAttr = NSAttributedString(
                string: item.description,
                attributes: [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: bodyColor, .paragraphStyle: ps]
            )
            let descH = max(ceil(descAttr.boundingRect(with: CGSize(width: descW, height: 10_000), options: [.usesLineFragmentOrigin], context: nil).height) + 8, 22)
            let rowH = descH

            ctx.setStrokeColor(borderGray.cgColor)
            ctx.move(to: CGPoint(x: margin, y: layout.y + rowH))
            ctx.addLine(to: CGPoint(x: margin + contentWidth, y: layout.y + rowH))
            ctx.strokePath()

            descAttr.draw(with: CGRect(x: x + 8, y: layout.y + 4, width: descW, height: rowH - 8), options: [.usesLineFragmentOrigin], context: nil)
            x += widths[0]

            let qtyStr = formatQuantity(item.quantity)
            let qty = NSAttributedString(string: qtyStr, attributes: bodyAttributes(size: 12))
            qty.draw(at: CGPoint(x: x + widths[1] - qty.size().width - 8, y: layout.y + 4))
            x += widths[1]

            let unit = NSAttributedString(string: "\(sym)\(formatMoney(item.unitPrice))", attributes: bodyAttributes(size: 12))
            unit.draw(at: CGPoint(x: x + widths[2] - unit.size().width - 8, y: layout.y + 4))
            x += widths[2]

            let amt = NSAttributedString(string: "\(sym)\(formatMoney(item.amount))", attributes: bodyAttributes(size: 12))
            amt.draw(at: CGPoint(x: x + widths[3] - amt.size().width - 8, y: layout.y + 4))

            layout.y += rowH
        }
    }

    private static func drawTotals(_ layout: inout Layout, invoice: Invoice, sym: String, totalPaid: Double, remaining: Double, hasPayments: Bool) {
        let boxW: CGFloat = 250
        let x = pageRect.width - margin - boxW
        var y = layout.y

        func row(_ left: String, _ right: String, bold: Bool = false, rightColor: UIColor = bodyColor) {
            let lf: [NSAttributedString.Key: Any] = bold
                ? [.font: UIFont.boldSystemFont(ofSize: 15), .foregroundColor: bodyColor]
                : bodyAttributes(size: 12)
            let rf: [NSAttributedString.Key: Any] = [
                .font: bold ? UIFont.boldSystemFont(ofSize: 15) : UIFont.systemFont(ofSize: 12),
                .foregroundColor: rightColor,
            ]
            let ls = NSAttributedString(string: left, attributes: lf)
            let rs = NSAttributedString(string: right, attributes: rf)
            ls.draw(at: CGPoint(x: x, y: y))
            rs.draw(at: CGPoint(x: x + boxW - rs.size().width, y: y))
            y += bold ? 22 : 16
        }

        row("Subtotal:", "\(sym)\(formatMoney(invoice.subtotal))")
        row("Tax (\(formatQuantity(invoice.taxRate))%):", "\(sym)\(formatMoney(invoice.tax))")
        y += 4
        ctxLineAbove(y: y, x: x, width: boxW, layout: layout)
        y += 8
        row("Total:", "\(sym)\(formatMoney(invoice.total))", bold: true)

        if hasPayments {
            y += 6
            ctxLineAbove(y: y, x: x, width: boxW, layout: layout)
            y += 8
            let green = UIColor(red: 0.30, green: 0.69, blue: 0.31, alpha: 1)
            let red = UIColor(red: 0.96, green: 0.26, blue: 0.21, alpha: 1)
            row("Total Paid:", "\(sym)\(formatMoney(totalPaid))", rightColor: green)
            y += 4
            ctxLineAbove(y: y, x: x, width: boxW, layout: layout)
            y += 8
            row("Remaining Balance:", "\(sym)\(formatMoney(remaining))", bold: true, rightColor: remaining > 0.0001 ? red : green)
        }

        layout.y = y + 4
    }

    private static func ctxLineAbove(y: CGFloat, x: CGFloat, width: CGFloat, layout: Layout) {
        let ctx = layout.cgContext
        ctx.setStrokeColor(borderGray.cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: x, y: y))
        ctx.addLine(to: CGPoint(x: x + width, y: y))
        ctx.strokePath()
    }

    private static func drawPaymentHistory(_ layout: inout Layout, payments: [Payment], sym: String) {
        NSAttributedString(string: "Payment History", attributes: sectionTitleAttributes()).draw(at: CGPoint(x: margin, y: layout.y))
        layout.y += 18

        for p in payments {
            let method = paymentMethodLabel(p.method)
            var left = "\(formatDate(iso: p.date)) - \(method)"
            if let n = p.notes, !n.isEmpty {
                left += "\n\(n)"
            }
            let leftAttr = NSAttributedString(string: left, attributes: bodyAttributes(size: 12))
            let rightAttr = NSAttributedString(string: "\(sym)\(formatMoney(p.amount))", attributes: bodyAttributes(size: 12))
            let h = max(leftAttr.boundingRect(with: CGSize(width: contentWidth - 120, height: 10_000), options: [.usesLineFragmentOrigin], context: nil).height, 16)
            layout.ensureSpace(h + 8)
            leftAttr.draw(with: CGRect(x: margin, y: layout.y, width: contentWidth - 120, height: h + 8), options: [.usesLineFragmentOrigin], context: nil)
            rightAttr.draw(at: CGPoint(x: pageRect.width - margin - rightAttr.size().width, y: layout.y))
            layout.y += h + 8
        }
    }

    private static func drawNotesBox(_ layout: inout Layout, title: String, body: String, accent: UIColor, fontSize: CGFloat = 12) {
        let pad: CGFloat = 10
        let innerW = contentWidth - pad * 2
        let titleAttr = NSMutableAttributedString(string: "\(title)\n", attributes: boldBodyAttributes(size: fontSize))
        let bodyAttr = NSAttributedString(string: body, attributes: bodyAttributes(size: fontSize))
        titleAttr.append(bodyAttr)
        let h = titleAttr.boundingRect(with: CGSize(width: innerW, height: 10_000), options: [.usesLineFragmentOrigin], context: nil).height + pad * 2

        layout.ensureSpace(h + 8)
        let rect = CGRect(x: margin, y: layout.y, width: contentWidth, height: ceil(h))
        let ctx = layout.cgContext
        ctx.setFillColor(lightGray.cgColor)
        ctx.fill(rect)
        ctx.setStrokeColor(accent.cgColor)
        ctx.setLineWidth(3)
        ctx.move(to: CGPoint(x: margin, y: layout.y))
        ctx.addLine(to: CGPoint(x: margin, y: layout.y + rect.height))
        ctx.strokePath()

        titleAttr.draw(with: CGRect(x: margin + pad, y: layout.y + pad, width: innerW, height: rect.height), options: [.usesLineFragmentOrigin], context: nil)
        layout.y += rect.height + 4
    }

    private static func drawBankFooter(_ layout: inout Layout, company: CompanyProfile) {
        let b = company.bankDetails
        var parts: [String] = [
            "Account Name: \(b.accountName)",
            "Account Number: \(b.accountNumber)",
        ]
        if let sc = b.sortCode, !sc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Sort Code: \(sc)")
        }
        let bodyText = parts.joined(separator: " | ")

        let title = NSAttributedString(string: "Bank Account Details", attributes: boldBodyAttributes(size: 12))
        let body = NSAttributedString(string: bodyText, attributes: bodyAttributes(size: 11))

        let titleH = title.size().height
        let bodyH = body.boundingRect(with: CGSize(width: contentWidth - 20, height: 10_000), options: [.usesLineFragmentOrigin], context: nil).height
        let boxH = titleH + bodyH + 24

        layout.ensureSpace(boxH)
        let top = layout.y
        let ctx = layout.cgContext
        ctx.setStrokeColor(borderGray.cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: margin, y: top))
        ctx.addLine(to: CGPoint(x: pageRect.width - margin, y: top))
        ctx.strokePath()

        ctx.setFillColor(lightGray.cgColor)
        ctx.fill(CGRect(x: margin, y: top, width: contentWidth, height: boxH))

        title.draw(at: CGPoint(x: margin + (contentWidth - title.size().width) / 2, y: top + 10))
        let ps = NSMutableParagraphStyle()
        ps.alignment = .center
        let centeredBody = NSMutableAttributedString(attributedString: body)
        centeredBody.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: centeredBody.length))
        centeredBody.draw(with: CGRect(x: margin + 10, y: top + 10 + titleH + 6, width: contentWidth - 20, height: bodyH + 8), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        layout.y = top + boxH
    }

    // MARK: - Helpers

    private struct Layout {
        let ctx: UIGraphicsPDFRendererContext
        let pageRect: CGRect
        let margin: CGFloat
        var y: CGFloat
        /// Current PDF page index (0-based), updated in `beginPage`.
        var pageIndex: Int = -1
        /// UIKit-style rects (origin top-left of page) for post-processing link annotations.
        var linkAnnotations: [(page: Int, rect: CGRect, url: URL)] = []

        var cgContext: CGContext { ctx.cgContext }

        init(ctx: UIGraphicsPDFRendererContext, pageRect: CGRect, margin: CGFloat) {
            self.ctx = ctx
            self.pageRect = pageRect
            self.margin = margin
            self.y = margin
        }

        mutating func beginPage() {
            ctx.beginPage()
            pageIndex += 1
            y = margin
        }

        mutating func ensureSpace(_ needed: CGFloat) {
            if y + needed > pageRect.height - margin {
                beginPage()
            }
        }

        mutating func drawCentered(_ text: String, font: UIFont, color: UIColor) {
            let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let s = NSAttributedString(string: text, attributes: attr)
            let w = s.size().width
            s.draw(at: CGPoint(x: pageRect.midX - w / 2, y: y))
            y += s.size().height + 4
        }

        mutating func drawWrapped(_ text: String, font: UIFont, color: UIColor, width: CGFloat, spacing: CGFloat) {
            let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let s = NSAttributedString(string: text, attributes: attr)
            let h = s.boundingRect(with: CGSize(width: width, height: 10_000), options: [.usesLineFragmentOrigin], context: nil).height
            s.draw(with: CGRect(x: margin, y: y, width: width, height: ceil(h) + 4), options: [.usesLineFragmentOrigin], context: nil)
            y += ceil(h) + spacing
        }

        /// Center-aligned paragraph (letterhead address / contact).
        mutating func drawCenteredParagraph(_ text: String, font: UIFont, color: UIColor, spacing: CGFloat) {
            let ps = NSMutableParagraphStyle()
            ps.alignment = .center
            let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: ps]
            let s = NSAttributedString(string: text, attributes: attr)
            let h = s.boundingRect(with: CGSize(width: contentWidth, height: 10_000), options: [.usesLineFragmentOrigin], context: nil).height
            s.draw(with: CGRect(x: margin, y: y, width: contentWidth, height: ceil(h) + 4), options: [.usesLineFragmentOrigin], context: nil)
            y += ceil(h) + spacing
        }
    }

    private static func bodyAttributes(size: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: UIFont.systemFont(ofSize: size), .foregroundColor: bodyColor]
    }

    private static func boldBodyAttributes(size: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: UIFont.boldSystemFont(ofSize: size), .foregroundColor: bodyColor]
    }

    private static func sectionTitleAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: UIFont.boldSystemFont(ofSize: 13),
            .foregroundColor: bodyColor,
        ]
    }

    private static func formatDate(iso: String) -> String {
        guard let d = parseISODate(iso) else { return iso }
        return gbDateFormatter.string(from: d)
    }

    private static func parseISODate(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return f.date(from: String(iso.prefix(10)))
    }

    private static func formatMoney(_ v: Double) -> String {
        String(format: "%.2f", v)
    }

    private static func formatQuantity(_ v: Double) -> String {
        v == floor(v) ? String(format: "%.0f", v) : String(format: "%.2f", v)
    }

    private static func paymentMethodLabel(_ m: PaymentMethod) -> String {
        switch m {
        case .BAC: return "Transfer"
        case .Card: return "Card payment"
        case .Cash: return "Cash"
        }
    }

    /// Resolves company logo for PDF: data URI, local file, `file://`, or **http/https** (fetched with timeout and size cap).
    private static func loadLogoImage(from logo: String?) async -> UIImage? {
        guard let raw = logo?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }

        if raw.hasPrefix("data:image"), let range = raw.range(of: ",") {
            let b64 = String(raw[range.upperBound...])
            if let data = Data(base64Encoded: b64) { return UIImage(data: data) }
            return nil
        }

        if raw.hasPrefix("file://"), let url = URL(string: raw) {
            return await Task.detached(priority: .utility) {
                (try? Data(contentsOf: url)).flatMap { UIImage(data: $0) }
            }.value
        }

        if raw.hasPrefix("/") {
            let url = URL(fileURLWithPath: raw)
            return await Task.detached(priority: .utility) {
                (try? Data(contentsOf: url)).flatMap { UIImage(data: $0) }
            }.value
        }

        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            guard !data.isEmpty, data.count <= 5 * 1024 * 1024 else { return nil }
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
}
