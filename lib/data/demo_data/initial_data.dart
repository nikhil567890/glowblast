import '../models/customer.dart';
import '../models/campaign.dart';
import '../models/group.dart';

class InitialData {
  static List<Customer> generate200Customers() {
    final now = DateTime.now();

    final List<String> firstNames = [
      'Aarav', 'Vivaan', 'Aditya', 'Vihaan', 'Arjun', 'Sai', 'Reyansh', 'Ayaan', 'Krishna', 'Ishaan',
      'Shaurya', 'Atharv', 'Advik', 'Pranav', 'Advaith', 'Aaryav', 'Dhruv', 'Kabir', 'Rohan', 'Kian',
      'Ananya', 'Diya', 'Saanvi', 'Aadhya', 'Pari', 'Isha', 'Navya', 'Riya', 'Myra', 'Anika',
      'Aarohi', 'Sara', 'Ahana', 'Avni', 'Tara', 'Anvi', 'Khushi', 'Shanaya', 'Sneha', 'Tanvi',
      'Vikram', 'Rajesh', 'Suresh', 'Ramesh', 'Sunil', 'Anil', 'Manoj', 'Deepak', 'Sanjay', 'Amit',
      'Pooja', 'Neha', 'Swati', 'Meera', 'Kavita', 'Sunita', 'Anita', 'Rekha', 'Divya', 'Shreya'
    ];

    final List<String> lastNames = [
      'Sharma', 'Verma', 'Iyer', 'Patel', 'Nair', 'Mehta', 'Singhania', 'Desai', 'Joshi', 'Rao',
      'Reddy', 'Gupta', 'Kapoor', 'Malhotra', 'Bhatia', 'Chopra', 'Saxena', 'Mukherjee', 'Chatterjee', 'Banerjee',
      'Menon', 'Pillai', 'Hegde', 'Shetty', 'Kamath', 'Kulkarni', 'Deshmukh', 'Patil', 'Pawar', 'Shinde'
    ];

    final List<Customer> list = [];

    // Exactly 200 demo customers
    for (int i = 0; i < 200; i++) {
      final firstName = firstNames[i % firstNames.length];
      final lastName = lastNames[(i * 3 + 7) % lastNames.length];
      final fullName = '$firstName $lastName';
      final phone = '+91 98${(70000000 + i * 11117).toString().substring(0, 8)}';

      // 12 Opted-Out customers (indices 0 to 11)
      final bool isOptedOut = i < 12;
      final createdAt = now.subtract(Duration(days: (200 - i) * 2));

      list.add(
        Customer(
          id: 'cust_${i + 1}',
          name: fullName,
          phone: phone,
          isOptedOut: isOptedOut,
          createdAt: createdAt,
        ),
      );
    }

    return list;
  }

  static List<Campaign> getPreloadedCampaigns() {
    final now = DateTime.now();

    return [
      Campaign(
        id: 'c1',
        name: 'Monsoon Glow Offer',
        month: 'Aug',
        date: DateTime(now.year, 8, 14, 11, 30),
        channel: 'WhatsApp',
        targetAudience: 'All Customers (Eligible 188)',
        messageContent: '🌸 Monsoon Glow Special! Indulge in our soothing Aromatherapy or Facial with flat 30% OFF this week at {spa_name}. Reply YES to reserve your slot!',
        recipients: 188,
        messagesSent: 188,
        delivered: 182,
        read: 132,
        failed: 6,
        replied: 44,
        status: 'Sent',
      ),
      Campaign(
        id: 'c2',
        name: 'Weekend Wellness',
        month: 'Sep',
        date: DateTime(now.year, 9, 12, 10, 0),
        channel: 'WhatsApp',
        targetAudience: 'Weekend Patrons',
        messageContent: '🌿 Weekend Wellness Escape! Rejuvenate your mind & body with our Signature Therapy. Complimentary Herbal Head Massage included! Book now: {spa_name}',
        recipients: 156,
        messagesSent: 156,
        delivered: 150,
        read: 98,
        failed: 6,
        replied: 31,
        status: 'Sent',
      ),
      Campaign(
        id: 'c3',
        name: 'Festive Radiance Ritual',
        month: 'Sep',
        date: DateTime(now.year, 9, 20, 9, 15),
        channel: 'WhatsApp',
        targetAudience: 'All Customers (Eligible 188)',
        messageContent: '✨ Step into tranquility! Treat yourself to our exclusive Festive Radiance Ritual at {spa_name} with special 25% savings throughout this month. Reply BOOK to reserve!',
        recipients: 188,
        messagesSent: 188,
        delivered: 184,
        read: 124,
        failed: 4,
        replied: 38,
        status: 'Sent',
      ),
    ];
  }

  static List<Campaign> getScheduledCampaigns() {
    final now = DateTime.now();

    return [
      Campaign(
        id: 'sched_1',
        name: 'Diwali Early Bird',
        month: 'Oct',
        date: now.add(const Duration(days: 5)),
        scheduledDate: DateTime(now.year, 10, 20, 10, 0),
        channel: 'WhatsApp',
        targetAudience: 'All Customers (Eligible 188)',
        messageContent: '✨ Diwali Glow Special! Book our Festive Glow Package and receive a complimentary Gold Facial. Valid until Diwali eve. Reserve now at {spa_name}!',
        recipients: 188,
        messagesSent: 188,
        delivered: 0,
        read: 0,
        failed: 0,
        replied: 0,
        status: 'Scheduled',
      ),
      Campaign(
        id: 'sched_2',
        name: 'Weekend Serenity',
        month: 'Oct',
        date: now.add(const Duration(days: 8)),
        scheduledDate: DateTime(now.year, 10, 25, 9, 0),
        channel: 'WhatsApp',
        targetAudience: 'Custom Selection (50)',
        messageContent: '💆 Relax, recharge & rejuvenate this weekend with our premium Hot Stone Therapy. Exclusively curated for our valued clients. Claim your slot at {spa_name}!',
        recipients: 50,
        messagesSent: 50,
        delivered: 0,
        read: 0,
        failed: 0,
        replied: 0,
        status: 'Scheduled',
      ),
    ];
  }

  static List<CustomerGroup> getInitialGroups(List<Customer> customers) {
    // Only user-creatable custom groups, no built-in groups tied to removed data
    final eligible = customers.where((c) => !c.isOptedOut).toList();
    return [
      CustomerGroup(
        id: 'grp_regular',
        name: 'Regular Patrons',
        description: 'Selected recurring clients for exclusive broadcasts',
        customerIds: eligible.take(50).map((c) => c.id).toList(),
        isSystemGroup: false,
      ),
    ];
  }

  static const List<Map<String, String>> templates = [
    {
      'id': 'tpl_diwali',
      'title': 'Diwali Offer',
      'category': 'Festival',
      'offer': 'Flat 35% OFF',
      'body': '✨ Sparkle & Glow this Diwali! Indulge in our Festive Radiance Ritual at {spa_name} with flat 35% OFF until Diwali eve. Treat yourself or gift a loved one! Reply YES to book.',
    },
    {
      'id': 'tpl_birthday',
      'title': 'Birthday Pampering',
      'category': 'Occasion',
      'offer': '25% Birthday Gift',
      'body': '🎂 Happy Birthday month, {name}! Celebrate your special day with our rejuvenating therapy at {spa_name}. Enjoy 25% OFF on any 90-minute treatment this month. Reply BOOK to reserve!',
    },
    {
      'id': 'tpl_festival',
      'title': 'Festival Special',
      'category': 'Festival',
      'offer': 'Festive Bundle 40% OFF',
      'body': '🎉 Celebrate the festivities with supreme tranquility! Enjoy our Festive Head-to-Toe Pampering Package with 40% OFF this weekend at {spa_name}. Limited slots available!',
    },
    {
      'id': 'tpl_weekend',
      'title': 'Weekend Package',
      'category': 'Weekend',
      'offer': 'Complimentary Head Massage',
      'body': '🌿 Reclaim your weekend calmness! Book any 60-min Full Body Massage this Saturday or Sunday and get a complimentary 30-min Herbal Head Massage at {spa_name}. Slots fill fast!',
    },
    {
      'id': 'tpl_reminder',
      'title': 'Appointment Reminder',
      'category': 'Service',
      'offer': 'Confirmed Slot',
      'body': '🌸 Hi {name}, this is a gentle reminder for your upcoming appointment at {spa_name}. Please arrive 10 minutes early to enjoy our warm herbal welcome tea.',
    },
    {
      'id': 'tpl_miss_you',
      'title': 'We Miss You',
      'category': 'Win-Back',
      'offer': '20% Welcome-Back Voucher',
      'body': '💆 We miss you, {name}! Your wellness journey is important to us. Here is an exclusive 20% welcome-back voucher for your next session at {spa_name}. Use code: GLOW20',
    },
    {
      'id': 'tpl_new_service',
      'title': 'New Therapy Launch',
      'category': 'Service',
      'offer': 'Introductory 30% OFF',
      'body': '✨ Introducing Himalayan Hot Stone Therapy! Experience deep muscle relaxation and renewed vitality. Be among the first to try it with 30% OFF introductory savings at {spa_name}.',
    },
    {
      'id': 'tpl_referral',
      'title': 'Referral Reward',
      'category': 'Loyalty',
      'offer': 'Complimentary Head Massage',
      'body': '🎁 Share the gift of relaxation! Refer a friend to {spa_name}. When they complete their first visit, you both receive a complimentary herbal head massage on your next visit.',
    },
    {
      'id': 'tpl_thank_you',
      'title': 'Thank You After Visit',
      'category': 'Service',
      'offer': 'Client Care',
      'body': '💚 Thank you for visiting {spa_name} today, {name}! We hope you feel thoroughly rejuvenated. Stay hydrated today, and we look forward to welcoming you back soon.',
    },
    {
      'id': 'tpl_membership',
      'title': 'Membership Renewal',
      'category': 'Membership',
      'offer': 'Extra 2 Months Free',
      'body': '⭐ Exclusive Member Offer: Renew your Annual Wellness Membership this week at {spa_name} and receive 2 additional months free + 2 complimentary guest passes!',
    },
    {
      'id': 'tpl_valentine',
      'title': 'Couples Aromatherapy',
      'category': 'Occasion',
      'offer': 'Couples Bliss 30% OFF',
      'body': '❤️ Romantic Bliss Awaits! Treat your partner to an unforgettable Couples Aromatherapy Ritual with candlelight, rose petals & herbal bath at {spa_name}. Reserve early!',
    },
    {
      'id': 'tpl_new_year',
      'title': 'New Year Rejuvenation',
      'category': 'Occasion',
      'offer': 'New Year Glow 25% OFF',
      'body': '🥂 Step into the season refreshed and glowing! Kickstart your wellness resolutions with our Detox Scrub & Massage combo at {spa_name}. Special 25% OFF all week!',
    },
  ];
}
