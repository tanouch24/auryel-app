/// Instantané persistable de l'onboarding — l'identité + les données
/// collectées pendant le parcours. Sérialisable en JSON pour la persistance
/// locale mock ; la même forme pourra être renvoyée par l'API réelle au Temps 2.
class OnboardingRecord {
  const OnboardingRecord({
    required this.userId,
    required this.selectedAdvisor,
    required this.firstName,
    required this.birthDate,
    required this.portraitData,
    required this.portraitFeedback,
    required this.onboardingCompleted,
  });

  final String? userId;
  final String? selectedAdvisor;
  final String? firstName;
  final DateTime? birthDate;
  final String? portraitData;
  final String? portraitFeedback;
  final bool onboardingCompleted;

  static const empty = OnboardingRecord(
    userId: null,
    selectedAdvisor: null,
    firstName: null,
    birthDate: null,
    portraitData: null,
    portraitFeedback: null,
    onboardingCompleted: false,
  );

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'selectedAdvisor': selectedAdvisor,
    'firstName': firstName,
    'birthDate': birthDate?.toIso8601String(),
    'portraitData': portraitData,
    'portraitFeedback': portraitFeedback,
    'onboardingCompleted': onboardingCompleted,
  };

  factory OnboardingRecord.fromJson(Map<String, dynamic> json) {
    final rawBirthDate = json['birthDate'] as String?;
    return OnboardingRecord(
      userId: json['userId'] as String?,
      selectedAdvisor: json['selectedAdvisor'] as String?,
      firstName: json['firstName'] as String?,
      birthDate: rawBirthDate == null ? null : DateTime.tryParse(rawBirthDate),
      portraitData: json['portraitData'] as String?,
      portraitFeedback: json['portraitFeedback'] as String?,
      onboardingCompleted: json['onboardingCompleted'] as bool? ?? false,
    );
  }
}
