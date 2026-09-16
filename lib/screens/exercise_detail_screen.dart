import 'package:flutter/material.dart';

import '../data/exercise.dart';
import '../theme/auryel_theme.dart';

class ExerciseDetailScreen extends StatelessWidget {
  const ExerciseDetailScreen({super.key, required this.exercise});
  final Exercise exercise;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Exercice')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        Text(
          exercise.categoryLabel.toUpperCase(),
          style: AuryelText.overline(color: AuryelColors.gold),
        ),
        const SizedBox(height: 10),
        Text(exercise.title, style: AuryelText.screenTitle()),
        const SizedBox(height: 12),
        Text(exercise.description, style: AuryelText.bodyText()),
        const SizedBox(height: 16),
        Text(
          '${exercise.durationLabel}  ·  ${exercise.level}',
          style: AuryelText.bodySecondary(),
        ),
        if (exercise.precautions.trim().isNotEmpty) ...[
          const SizedBox(height: 18),
          Text('À garder en tête', style: AuryelText.sectionTitle()),
          const SizedBox(height: 6),
          Text(exercise.precautions, style: AuryelText.bodyText()),
        ],
        const SizedBox(height: 24),
        Text('Déroulé', style: AuryelText.sectionTitle()),
        const SizedBox(height: 8),
        for (final step in exercise.steps)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 15,
              backgroundColor: AuryelColors.surfaceLight,
              child: Text(
                '${step.order}',
                style: AuryelText.body(
                  fontSize: 12,
                  color: AuryelColors.goldLight,
                ),
              ),
            ),
            title: Text(step.title, style: AuryelText.cardTitle()),
            subtitle: Text(step.instruction, style: AuryelText.bodySecondary()),
            trailing: step.seconds == null
                ? null
                : Text('${step.seconds}s', style: AuryelText.bodySecondary()),
          ),
        const SizedBox(height: 20),
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ExerciseSessionScreen(exercise: exercise),
              ),
            ),
            child: const Text('Commencer'),
          ),
        ),
      ],
    ),
  );
}

class ExerciseSessionScreen extends StatelessWidget {
  const ExerciseSessionScreen({super.key, required this.exercise});
  final Exercise exercise;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(exercise.title)),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Prends ton temps.', style: AuryelText.screenTitle()),
        const SizedBox(height: 10),
        Text(
          'Suis les étapes à ton rythme, sans chercher la performance.',
          style: AuryelText.bodyText(),
        ),
        const SizedBox(height: 24),
        for (final step in exercise.steps)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(step.title, style: AuryelText.cardTitle()),
                  const SizedBox(height: 6),
                  Text(step.instruction, style: AuryelText.bodyText()),
                ],
              ),
            ),
          ),
        const SizedBox(height: 20),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Terminer'),
        ),
      ],
    ),
  );
}
