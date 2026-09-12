/// Mirrors `GET /v1/orders/:orderId/invoice`'s response (routes/invoices.ts,
/// Sprint 8). `url` is a short-lived signed URL, minted fresh on every
/// request -- never cached across sessions, and re-fetched rather than
/// reused if it's been a while since the last request.
class InvoiceLink {
  const InvoiceLink({
    required this.invoiceNumber,
    required this.generatedAt,
    required this.total,
    required this.url,
  });

  final String invoiceNumber;
  final DateTime generatedAt;
  final int total;
  final String url;

  factory InvoiceLink.fromJson(Map<String, dynamic> json) {
    return InvoiceLink(
      invoiceNumber: json['invoiceNumber'] as String,
      generatedAt: DateTime.parse(json['generatedAt'] as String),
      total: json['total'] as int,
      url: json['url'] as String,
    );
  }
}
