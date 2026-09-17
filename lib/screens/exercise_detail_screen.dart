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
        if (exercise.imageUrl != null) ...[
          _ExerciseImage(url: exercise.imageUrl!),
          const SizedBox(height: 20),
        ],
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

class _ExerciseImage extends StatelessWidget {
  const _ExerciseImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) => AspectRatio(
    // Les illustrations montrent des postures : un cadre plus haut évite de
    // couper la tête, les mains ou les jambes comme le faisait le 16:10.
    aspectRatio: 4 / 5,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: ColoredBox(
        color: AuryelColors.surfaceLight,
        child: Image.network(
          url,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : const _ExerciseImageFallback(),
          errorBuilder: (context, error, stackTrace) =>
              const _ExerciseImageFallback(),
        ),
      ),
    ),
  );
}

class _ExerciseImageFallback extends StatelessWidget {
  const _ExerciseImageFallback();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AuryelColors.surfaceLight,
    child: Center(
      child: Icon(
        Icons.self_improvement_outlined,
        color: AuryelColors.goldLight,
        size: 38,
      ),
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

class ExerciseDailySessionScreen extends StatefulWidget {
  const ExerciseDailySessionScreen({super.key, required this.exercises});
  final List<Exercise> exercises;

  @override
  State<ExerciseDailySessionScreen> createState() =>
      _ExerciseDailySessionScreenState();
}

class _ExerciseDailySessionScreenState extends State<ExerciseDailySessionScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final exercise = widget.exercises[_index];
    final last = _index == widget.exercises.length - 1;
    return Scaffold(
      appBar: AppBar(title: Text('Exercice ${_index + 1}/5')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          if (exercise.imageUrl != null) _ExerciseImage(url: exercise.imageUrl!),
          const SizedBox(height: 18),
          Text(exercise.title, style: AuryelText.screenTitle()),
          const SizedBox(height: 10),
          Text(exercise.description, style: AuryelText.bodyText()),
          const SizedBox(height: 20),
          for (final step in exercise.steps)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text('${step.order}')),
              title: Text(step.title),
              subtitle: Text(step.instruction),
              trailing: step.seconds == null ? null : Text('${step.seconds}s'),
            ),
          const SizedBox(height: 20),
          FilledButton(
            key: Key(last ? 'daily-exercise-finish' : 'daily-exercise-next'),
            onPressed: () {
              if (last) {
                Navigator.of(context).pushReplacement(MaterialPageRoute(
                  builder: (_) => const _DailyExerciseCompleteScreen(),
                ));
              } else {
                setState(() => _index++);
              }
            },
            child: Text(last ? 'Séance terminée' : 'Exercice suivant'),
          ),
        ],
      ),
    );
  }
}

class _DailyExerciseCompleteScreen extends StatelessWidget {
  const _DailyExerciseCompleteScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Séance terminée')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle_outline, size: 64, color: AuryelColors.goldLight),
          const SizedBox(height: 18),
          Text('Tu as pris ce moment pour toi.', style: AuryelText.screenTitle(), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Retour au Bien-être')),
        ]),
      ),
    ),
  );
}
