import 'dart:math';

import 'package:flutter/widgets.dart';

import '../data/onboarding_record.dart';
import '../data/onboarding_repository.dart';

/// État partagé de l'appli — identité + progression onboarding. Le
/// `userId` est `null` tant que le compte (mock) n'a pas été "créé" ; ce
/// n'est jamais l'email qui sert d'identité technique, seulement ce
/// `userId` interne (le futur backend utilisera un `user_id` Auryel réel).
class AuryelState extends ChangeNotifier {
  AuryelState({required this.repository, OnboardingRecord? initial})
    : userId = initial?.userId,
      selectedAdvisor = initial?.selectedAdvisor,
      firstName = initial?.firstName,
      birthDate = initial?.birthDate,
      portraitData = initial?.portraitData,
      portraitFeedback = initial?.portraitFeedback,
      onboardingCompleted = initial?.onboardingCompleted ?? false;

  final OnboardingRepository repository;

  String? userId;
  String? selectedAdvisor;
  String? firstName;
  DateTime? birthDate;
  String? portraitData;
  String? portraitFeedback;
  bool onboardingCompleted;

  void selectAdvisor(String advisorName) {
    selectedAdvisor = advisorName;
    notifyListeners();
  }

  void setFirstName(String name) {
    firstName = name;
    notifyListeners();
  }

  void setBirthDate(DateTime date) {
    birthDate = date;
    notifyListeners();
  }

  void setPortraitData(String text) {
    portraitData = text;
    notifyListeners();
  }

  void setPortraitFeedback(String text) {
    portraitFeedback = text;
    notifyListeners();
  }

  /// Simule une authentification réussie (Apple / Google / email — visuel
  /// uniquement) : génère un identifiant factice, clôt l'onboarding, et
  /// persiste l'instantané via le repository courant.
  Future<void> completeOnboarding() async {
    userId = _generateTempUserId();
    onboardingCompleted = true;
    await repository.save(_toRecord());
    notifyListeners();
  }

  OnboardingRecord _toRecord() => OnboardingRecord(
    userId: userId,
    selectedAdvisor: selectedAdvisor,
    firstName: firstName,
    birthDate: birthDate,
    portraitData: portraitData,
    portraitFeedback: portraitFeedback,
    onboardingCompleted: onboardingCompleted,
  );

  /// Reset DEBUG uniquement — efface les données mock d'onboarding pour
  /// permettre de rejouer le parcours. Jamais exposé comme fonctionnalité
  /// utilisateur finale (voir le geste caché sur l'icône profil).
  Future<void> debugReset() async {
    await repository.clear();
    userId = null;
    selectedAdvisor = null;
    firstName = null;
    birthDate = null;
    portraitData = null;
    portraitFeedback = null;
    onboardingCompleted = false;
    notifyListeners();
  }

  static String _generateTempUserId() {
    final random = Random();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'temp_$hex';
  }
}

/// Fournit [AuryelState] à tout l'arbre de widgets. `AuryelStateScope.of`
/// s'abonne aux changements (rebuild automatique sur `notifyListeners`).
class AuryelStateScope extends InheritedNotifier<AuryelState> {
  const AuryelStateScope({
    super.key,
    required AuryelState state,
    required super.child,
  }) : super(notifier: state);

  static AuryelState of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AuryelStateScope>();
    assert(
      scope != null,
      'AuryelStateScope introuvable dans l’arbre de widgets.',
    );
    return scope!.notifier!;
  }
}
