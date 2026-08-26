import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../screens/home_screen.dart';
import '../screens/placeholder_screen.dart';
import '../theme/auryel_theme.dart';

/// Coquille de navigation : 3 onglets, contenu réel pour "Accueil",
/// placeholders stylés pour les 2 autres en attendant leur écran.
class MainNavShell extends StatefulWidget {
  const MainNavShell({super.key});

  @override
  State<MainNavShell> createState() => _MainNavShellState();
}

class _MainNavShellState extends State<MainNavShell> {
  int _index = 0;

  static const _screens = [
    HomeScreen(),
    PlaceholderScreen(
      title: 'Mes cartes du jour',
      icon: PhosphorIconsRegular.cardsThree,
    ),
    PlaceholderScreen(
      title: 'Ton moment',
      icon: PhosphorIconsRegular.flowerLotus,
      subtitle: 'Quelques minutes pour ralentir et revenir à toi.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: _AuryelTabBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}

class _AuryelTabBar extends StatelessWidget {
  const _AuryelTabBar({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _tabs = [
    (label: 'Accueil', icon: PhosphorIconsRegular.house, activeIcon: PhosphorIconsFill.house),
    (label: 'Mes cartes', icon: PhosphorIconsRegular.cardsThree, activeIcon: PhosphorIconsFill.cardsThree),
    (label: 'Méditer', icon: PhosphorIconsRegular.flowerLotus, activeIcon: PhosphorIconsFill.flowerLotus),
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AuryelColors.surface,
        border: Border(top: BorderSide(color: AuryelColors.warmBorder, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: List.generate(_tabs.length, (i) {
              final tab = _tabs[i];
              final active = i == currentIndex;
              final color = active ? AuryelColors.gold : AuryelColors.textMuted;
              return Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      PhosphorIcon(active ? tab.activeIcon : tab.icon, size: 22, color: color),
                      const SizedBox(height: 4),
                      Text(
                        tab.label,
                        style: AuryelText.body(
                          fontSize: 10.5,
                          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                          color: color,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
