// domain.dart — a customer's own domain (public_domain() in domains.py).

class DnsRecord {
  final String type;    // "TXT"
  final String host;    // "_mailspace"
  final String value;   // "mailspace-verify=…"
  final String purpose; // "Proves you own this domain"

  DnsRecord({required this.type, required this.host, required this.value, required this.purpose});

  factory DnsRecord.fromJson(Map<String, dynamic> json) => DnsRecord(
        type: json['type'] as String? ?? 'TXT',
        host: json['host'] as String? ?? '',
        value: json['value'] as String? ?? '',
        purpose: json['purpose'] as String? ?? '',
      );
}

/// An address created on a verified domain, e.g. info@yourbusiness.com
class DomainAddress {
  final String id;
  final String email;

  DomainAddress({required this.id, required this.email});

  factory DomainAddress.fromJson(Map<String, dynamic> json) =>
      DomainAddress(id: json['id'] as String, email: json['email'] as String);
}

class Domain {
  final String id;
  final String name;      // yourbusiness.com
  final String status;    // 'pending' or 'verified'
  final DateTime? createdAt;
  final DateTime? verifiedAt;
  final List<DnsRecord> dnsRecords;
  final List<DomainAddress> addresses;

  Domain({
    required this.id,
    required this.name,
    required this.status,
    this.createdAt,
    this.verifiedAt,
    this.dnsRecords = const [],
    this.addresses = const [],
  });

  bool get isVerified => status == 'verified';

  factory Domain.fromJson(Map<String, dynamic> json) => Domain(
        id: json['id'] as String,
        name: json['name'] as String,
        status: json['status'] as String? ?? 'pending',
        createdAt: json['created_at'] is String ? DateTime.tryParse(json['created_at'])?.toLocal() : null,
        verifiedAt: json['verified_at'] is String ? DateTime.tryParse(json['verified_at'])?.toLocal() : null,
        dnsRecords: (json['dns_records'] as List? ?? [])
            .map((r) => DnsRecord.fromJson(r as Map<String, dynamic>))
            .toList(),
        addresses: (json['addresses'] as List? ?? [])
            .map((a) => DomainAddress.fromJson(a as Map<String, dynamic>))
            .toList(),
      );
}
