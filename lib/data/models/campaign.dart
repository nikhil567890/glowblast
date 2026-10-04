class Campaign {
  final String id;
  final String name;
  final String month;
  final DateTime date;
  final String channel; // 'WhatsApp'
  final String targetAudience;
  final String messageContent;
  final int recipients; // Eligible customers count
  final int messagesSent; // recipients * 1
  final int delivered;
  final int read;
  final int failed;
  final int replied;
  final String status; // 'Sent', 'Scheduled', 'Accepted'
  final DateTime? scheduledDate;
  final bool isRealTest; // True if sent through real Meta WhatsApp Cloud API backend
  final String? backendCampaignId;

  Campaign({
    required this.id,
    required this.name,
    required this.month,
    required this.date,
    this.channel = 'WhatsApp',
    required this.targetAudience,
    required this.messageContent,
    required this.recipients,
    required this.messagesSent,
    required this.delivered,
    required this.read,
    required this.failed,
    required this.replied,
    this.status = 'Sent',
    this.scheduledDate,
    this.isRealTest = false,
    this.backendCampaignId,
  });

  double get deliveryRate => messagesSent > 0 ? (delivered / messagesSent) * 100 : 0.0;
  double get readRate => delivered > 0 ? (read / delivered) * 100 : 0.0;
  double get replyRate => read > 0 ? (replied / read) * 100 : 0.0;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'month': month,
    'date': date.toIso8601String(),
    'channel': channel,
    'targetAudience': targetAudience,
    'messageContent': messageContent,
    'recipients': recipients,
    'messagesSent': messagesSent,
    'delivered': delivered,
    'read': read,
    'failed': failed,
    'replied': replied,
    'status': status,
    'scheduledDate': scheduledDate?.toIso8601String(),
    'isRealTest': isRealTest,
    'backendCampaignId': backendCampaignId,
  };

  factory Campaign.fromJson(Map<String, dynamic> json) {
    final recipients = (json['recipients'] as num?)?.toInt() ?? 0;
    return Campaign(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      month: json['month'] as String? ?? 'Oct',
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      channel: 'WhatsApp',
      targetAudience: json['targetAudience'] as String? ?? 'All Customers',
      messageContent: json['messageContent'] as String? ?? '',
      recipients: recipients,
      messagesSent: (json['messagesSent'] as num?)?.toInt() ?? recipients,
      delivered: (json['delivered'] as num?)?.toInt() ?? 0,
      read: (json['read'] as num?)?.toInt() ?? 0,
      failed: (json['failed'] as num?)?.toInt() ?? 0,
      replied: (json['replied'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'Sent',
      scheduledDate: json['scheduledDate'] != null ? DateTime.tryParse(json['scheduledDate'] as String) : null,
      isRealTest: json['isRealTest'] as bool? ?? false,
      backendCampaignId: json['backendCampaignId'] as String?,
    );
  }

  Campaign copyWith({
    String? id,
    String? name,
    String? month,
    DateTime? date,
    String? channel,
    String? targetAudience,
    String? messageContent,
    int? recipients,
    int? messagesSent,
    int? delivered,
    int? read,
    int? failed,
    int? replied,
    String? status,
    DateTime? scheduledDate,
    bool? isRealTest,
    String? backendCampaignId,
  }) {
    return Campaign(
      id: id ?? this.id,
      name: name ?? this.name,
      month: month ?? this.month,
      date: date ?? this.date,
      channel: channel ?? this.channel,
      targetAudience: targetAudience ?? this.targetAudience,
      messageContent: messageContent ?? this.messageContent,
      recipients: recipients ?? this.recipients,
      messagesSent: messagesSent ?? this.messagesSent,
      delivered: delivered ?? this.delivered,
      read: read ?? this.read,
      failed: failed ?? this.failed,
      replied: replied ?? this.replied,
      status: status ?? this.status,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      isRealTest: isRealTest ?? this.isRealTest,
      backendCampaignId: backendCampaignId ?? this.backendCampaignId,
    );
  }
}
