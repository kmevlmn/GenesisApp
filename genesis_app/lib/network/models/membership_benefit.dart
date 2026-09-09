enum MembershipBenefitDisplay { enhanced, locked, included }

/// Display metadata shared by all Pro plans; never used for authorization.
class MembershipBenefit {
  const MembershipBenefit({
    required this.code,
    required this.title,
    required this.iconKey,
    required this.displayType,
  });

  factory MembershipBenefit.fromJson(Map<String, dynamic> json) {
    String field(String name) {
      final value = json[name];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Invalid membership benefit $name');
      }
      return value;
    }

    return MembershipBenefit(
      code: field('code'),
      title: field('title'),
      iconKey: field('icon_key'),
      displayType: switch (json['display_type']) {
        'enhanced' => MembershipBenefitDisplay.enhanced,
        'locked' => MembershipBenefitDisplay.locked,
        'included' => MembershipBenefitDisplay.included,
        _ => throw const FormatException('Invalid membership benefit display'),
      },
    );
  }

  final String code;
  final String title;
  final String iconKey;
  final MembershipBenefitDisplay displayType;

  Map<String, Object?> toJson() => {
    'code': code,
    'title': title,
    'icon_key': iconKey,
    'display_type': displayType.name,
  };
}
