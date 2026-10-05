// Typed models mirroring the Redefine API JSON.

class AuthUser {
  final String id, name, email, role, initials, color;
  final String? linkedId;
  AuthUser.fromJson(Map<String, dynamic> j)
      : id = j['id'] ?? '',
        name = j['name'] ?? '',
        email = j['email'] ?? '',
        role = j['role'] ?? 'customer',
        initials = j['initials'] ?? '',
        color = j['color'] ?? 'lime',
        linkedId = j['linkedId'] as String?;
}

class AuthResult {
  final String token;
  final AuthUser user;
  AuthResult(this.token, this.user);
  AuthResult.fromJson(Map<String, dynamic> j)
      : token = j['token'] ?? '',
        user = AuthUser.fromJson((j['user'] ?? const {}) as Map<String, dynamic>);
}

T? _as<T>(dynamic v) => v is T ? v : null;
int _int(dynamic v, [int d = 0]) => v is num ? v.toInt() : d;
bool _bool(dynamic v) => v == true;

class Customer {
  final String id, name, initials, color, status, email, phone, address, secondary, since;
  Customer.fromJson(Map<String, dynamic> j)
      : id = j['id'] ?? '',
        name = j['name'] ?? '',
        initials = j['initials'] ?? '',
        color = j['color'] ?? 'paper',
        status = j['status'] ?? 'active',
        email = j['email'] ?? '',
        phone = j['phone'] ?? '',
        address = j['address'] ?? '',
        secondary = j['secondary'] ?? '',
        since = j['since'] ?? '';
}

class Property {
  final String id, customerId, name, address, illustration, serviceType, nextVisitLabel;
  final int visitNumber, totalVisits;
  Property.fromJson(Map<String, dynamic> j)
      : id = j['id'] ?? '',
        customerId = j['customerId'] ?? '',
        name = j['name'] ?? '',
        address = j['address'] ?? '',
        illustration = j['illustration'] ?? 'house',
        serviceType = j['serviceType'] ?? 'biweekly',
        nextVisitLabel = j['nextVisitLabel'] ?? '',
        visitNumber = _int(j['visitNumber'], 1),
        totalVisits = _int(j['totalVisits'], 16);
}

class Quote {
  final String id, customerName, customerInitials, email, phone, propertyName, address,
      propertyDesc, status, submittedAt, note, program;
  final String? crewVisit;
  final int? biweeklyPrice, oneTimePrice;
  final int pendingDays;
  Quote.fromJson(Map<String, dynamic> j)
      : id = j['id'] ?? '',
        customerName = j['customerName'] ?? '',
        customerInitials = j['customerInitials'] ?? '',
        email = j['email'] ?? '',
        phone = j['phone'] ?? '',
        propertyName = j['propertyName'] ?? '',
        address = j['address'] ?? '',
        propertyDesc = j['propertyDesc'] ?? '',
        status = j['status'] ?? 'pending',
        submittedAt = j['submittedAt'] ?? '',
        note = j['note'] ?? '',
        program = j['program'] ?? '',
        crewVisit = _as<String>(j['crewVisit']),
        biweeklyPrice = _as<num>(j['biweeklyPrice'])?.toInt(),
        oneTimePrice = _as<num>(j['oneTimePrice'])?.toInt(),
        pendingDays = _int(j['pendingDays']);
}

class CrewMember {
  final String id, name, initials, color, status, email, phone, experience, appliedAgo;
  final int jobsThisWeek, payThisWeek;
  CrewMember.fromJson(Map<String, dynamic> j)
      : id = j['id'] ?? '',
        name = j['name'] ?? '',
        initials = j['initials'] ?? '',
        color = j['color'] ?? 'paper',
        status = j['status'] ?? 'active',
        email = j['email'] ?? '',
        phone = j['phone'] ?? '',
        experience = j['experience'] ?? '',
        appliedAgo = j['appliedAgo'] ?? '',
        jobsThisWeek = _int(j['jobsThisWeek']),
        payThisWeek = _int(j['payThisWeek']);
}

class JobCard {
  final String id, propertyName, address, customerName, phase, date, weekOf, status, time, eta;
  final int maxCrew, payPerCrew, slotsFilled;
  final bool goTogether;
  final List<String> crewIds;
  JobCard.fromJson(Map<String, dynamic> j)
      : id = j['id'] ?? '',
        propertyName = j['propertyName'] ?? '',
        address = j['address'] ?? '',
        customerName = j['customerName'] ?? '',
        phase = j['phase'] ?? 'aeration',
        date = j['date'] ?? '',
        weekOf = j['weekOf'] ?? '',
        status = j['status'] ?? 'toPost',
        time = j['time'] ?? '',
        eta = j['eta'] ?? '',
        maxCrew = _int(j['maxCrew'], 1),
        payPerCrew = _int(j['payPerCrew']),
        slotsFilled = _int(j['slotsFilled']),
        goTogether = _bool(j['goTogether']),
        crewIds = ((j['crewIds'] as List?) ?? const []).map((e) => e.toString()).toList();
}

class Visit {
  final String id, propertyId, date, weekday, ago, crew, crewInitials, phase, note;
  final int durationMin, visitNumber, totalVisits;
  Visit.fromJson(Map<String, dynamic> j)
      : id = j['id'] ?? '',
        propertyId = j['propertyId'] ?? '',
        date = j['date'] ?? '',
        weekday = j['weekday'] ?? '',
        ago = j['ago'] ?? '',
        crew = j['crew'] ?? '',
        crewInitials = j['crewInitials'] ?? '',
        phase = j['phase'] ?? 'aeration',
        note = j['note'] ?? '',
        durationMin = _int(j['durationMin']),
        visitNumber = _int(j['visitNumber'], 1),
        totalVisits = _int(j['totalVisits'], 16);
}
