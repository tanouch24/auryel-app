/// Métadonnées NON sensibles de l'application, jointes au formulaire de
/// support pour aider le diagnostic. Aucune donnée personnelle ici.
///
/// [kAppVersion] est surchargeable au build :
///   flutter build apk --dart-define=AURYEL_APP_VERSION=1.0.3
/// Sinon repli sur la version courante du `pubspec.yaml`.
const String kAppVersion = String.fromEnvironment(
  'AURYEL_APP_VERSION',
  defaultValue: '1.0.0',
);
