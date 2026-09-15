import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/data/onboarding_record.dart';
import 'package:auryel/data/onboarding_repository.dart';
import 'package:auryel/data/shop_cart_store.dart';
import 'package:auryel/data/shop_checkout_service.dart';
import 'package:auryel/data/shop_product.dart';
import 'package:auryel/screens/bibliotheque_screen.dart';
import 'package:auryel/screens/boutique_coming_soon_screen.dart';
import 'package:auryel/screens/boutique_screen.dart';
import 'package:auryel/screens/cart_screen.dart';
import 'package:auryel/screens/dashboard_screen.dart';
import 'package:auryel/screens/product_detail_screen.dart';
import 'package:auryel/state/auryel_state.dart';
import 'package:auryel/widgets/main_nav_shell.dart';

// ===========================================================================
// BOUTIQUE V1 — onglet Boutique (remplace « Bibliothèque » dans la bottom nav).
// ===========================================================================

AuryelState _state() => AuryelState(
  repository: LocalOnboardingRepository(),
  initial: OnboardingRecord(
    userId: 'u-1',
    selectedAdvisor: 'Séléna',
    firstName: 'Nina',
    birthDate: DateTime(1990, 1, 1),
    portraitData: 'x',
    portraitFeedback: 'y',
    onboardingCompleted: true,
  ),
);

late ShopCartStore _cart;

Widget _wrapCart(Widget child) => ShopCartScope(
  store: _cart,
  child: MaterialApp(home: child),
);

Widget _nav() => AuryelStateScope(
  state: _state(),
  child: ShopCartScope(
    store: _cart,
    child: const MaterialApp(home: MainNavShell()),
  ),
);

Widget _boutique() => _wrapCart(const BoutiqueScreen());

// AUDIT ACCUEIL/PARCOURS — Accueil affiche désormais une mission « Consultation »
// (même libellé que le parcours bien-être serveur) : le texte seul ne
// distingue plus l'onglet de bottom nav de cette ligne de mission (les deux
// écrans restent montés simultanément, IndexedStack). On restreint donc la
// recherche à la barre d'onglets elle-même.
Finder _tab(String label) => find.descendant(
  of: find.byKey(const Key('auryel-bottom-tab-bar')),
  matching: find.widgetWithText(InkWell, label),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ShopCartStore.debugResetInstance();
    _cart = ShopCartStore(autoLoad: false);
  });
  testWidgets('A/B/C/D — bottom nav V1 = 5 onglets avec Boutique', (t) async {
    await t.pumpWidget(_nav());
    await t.pumpAndSettle();

    expect(_tab('Accueil'), findsOneWidget);
    expect(_tab('Bien-être'), findsOneWidget);
    expect(_tab('Consultation'), findsOneWidget);
    expect(_tab('Boutique'), findsOneWidget);
    expect(_tab('Réveil'), findsOneWidget);

    expect(_tab('Méditation'), findsNothing);
    expect(_tab('Bibliothèque'), findsNothing);
    expect(_tab('Mon espace'), findsNothing);
  });

  testWidgets('E — V1 : la Boutique expose seulement son écran bientôt disponible — aucun '
      'catalogue / prix / panier exposé par la coquille', (t) async {
    await t.pumpWidget(_nav());
    await t.pumpAndSettle();

    expect(_tab('Boutique'), findsOneWidget);
    await t.tap(_tab('Boutique'));
    await t.pumpAndSettle();
    expect(find.byType(BoutiqueComingSoonScreen), findsOneWidget);
    expect(find.byType(BoutiqueScreen), findsNothing);
    expect(find.byType(CartScreen), findsNothing);
    expect(find.byType(ProductDetailScreen), findsNothing);
    expect(find.byTooltip('Mon panier'), findsNothing);
    // Les produits/panier Boutique restent absents de l'écran V1.
    for (final p in kShopProducts) {
      expect(find.text(p.name), findsNothing, reason: p.name);
    }
  });

  testWidgets(
    'E bis — l\'écran « À venir » (conservé hors nav) : aucune date / '
    '« bientôt » insistant / compte à rebours',
    (t) async {
      await t.pumpWidget(const MaterialApp(home: BoutiqueComingSoonScreen()));
      await t.pumpAndSettle();

      expect(find.text('Bientôt disponible'), findsOneWidget);
      expect(find.textContaining('jours'), findsNothing);
      expect(find.textContaining('202'), findsNothing); // pas d'année/date
    },
  );

  testWidgets('F/G — catégories affichées + « Tout » par défaut', (t) async {
    await t.pumpWidget(_boutique());
    await t.pump();

    expect(find.text('Tout'), findsOneWidget);
    for (final c in ShopCategory.values) {
      expect(find.text(c.label), findsWidgets);
    }
  });

  testWidgets('H — au moins 8 produits de démonstration', (t) async {
    expect(kShopProducts.length, greaterThanOrEqualTo(8));

    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(390, 4000);
    addTearDown(t.view.reset);

    await t.pumpWidget(_boutique());
    await t.pump();

    for (final p in kShopProducts) {
      expect(find.text(p.name), findsWidgets, reason: p.name);
    }
  });

  testWidgets('I — le filtre catégorie agit sur la grille', (t) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(430, 4000);
    addTearDown(t.view.reset);

    await t.pumpWidget(_boutique());
    await t.pump();

    // « Tout » : un produit « pierres » non mis en avant est visible.
    expect(find.text('Améthyste'), findsOneWidget); // pierres, non featured
    expect(find.text('Oracle introspectif Auryel'), findsOneWidget); // tarot

    // chips 0 (« Tout ») et 1 (« Tarot & Oracles ») visibles sans scroll à 430 dp
    await t.tap(
      find.widgetWithText(InkWell, 'Tarot & Oracles').first,
      warnIfMissed: false,
    );
    await t.pumpAndSettle();

    expect(find.text('Améthyste'), findsNothing); // filtré
    expect(find.text('Oracle introspectif Auryel'), findsOneWidget); // gardé

    await t.tap(find.widgetWithText(InkWell, 'Tout'), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(find.text('Améthyste'), findsOneWidget);
  });

  testWidgets('J — la carte produit affiche nom + prix + CTA', (t) async {
    await t.pumpWidget(_boutique());
    await t.pump();

    expect(find.text('Tarot de Marseille'), findsWidgets);
    expect(find.text('24,90 €'), findsWidgets);
    expect(find.textContaining('Voir le produit'), findsWidgets);
  });

  testWidgets('K/L — tap produit -> fiche ; CTA = « Ajouter au panier », '
      'aucun bouton « Acheter »', (t) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(390, 4000);
    addTearDown(t.view.reset);

    await t.pumpWidget(_boutique());
    await t.pump();

    await t.tap(find.text('Améthyste')); // non featured -> carte de grille
    await t.pumpAndSettle();

    expect(find.byType(ProductDetailScreen), findsOneWidget);
    expect(find.text('14,90 €'), findsWidgets);

    final cta = find.text('Ajouter au panier');
    expect(cta, findsOneWidget);
    expect(find.text('Disponible prochainement'), findsNothing);
    expect(find.text('Acheter'), findsNothing);
    expect(find.text('Acheter maintenant'), findsNothing);
    expect(find.text('Payer'), findsNothing);

    // N — ajout depuis la fiche : retour visuel + panier alimenté.
    await t.tap(cta);
    await t.pump();
    expect(find.text('Ajouté au panier'), findsOneWidget);
    expect(_cart.quantityFor('amethyste'), 1);
  });

  test(
    'M — seam checkout : indisponible, lève ShopCheckoutUnavailable',
    () async {
      expect(ShopCheckoutService.checkoutAvailable, isFalse);
      await expectLater(
        const ShopCheckoutService().startCheckout(kShopProducts.first),
        throwsA(isA<ShopCheckoutUnavailable>()),
      );
      await expectLater(
        const ShopCheckoutService().startCartCheckout(const [
          CartItem(productId: 'amethyste', quantity: 2),
        ]),
        throwsA(isA<ShopCheckoutUnavailable>()),
      );
    },
  );

  testWidgets(
    'O — panier visible depuis la Boutique + badge = total d’unités',
    (t) async {
      await t.pumpWidget(_boutique());
      await t.pump();

      // Panier vide -> pas de badge chiffré.
      expect(find.byTooltip('Mon panier'), findsOneWidget);
      expect(find.text('1'), findsNothing);

      _cart.addProduct(kShopProducts.firstWhere((p) => p.id == 'amethyste'));
      _cart.addProduct(kShopProducts.firstWhere((p) => p.id == 'amethyste'));
      _cart.addProduct(kShopProducts.firstWhere((p) => p.id == 'quartz-rose'));
      await t.pump();

      expect(find.text('3'), findsOneWidget); // 2 + 1 unités, pas 2 lignes

      await t.tap(find.byTooltip('Mon panier'));
      await t.pumpAndSettle();
      expect(find.byType(CartScreen), findsOneWidget);
      expect(find.text('Mon panier'), findsOneWidget);
      expect(find.text('Sous-total'), findsOneWidget);
      expect(find.text('44,70 €'), findsOneWidget); // 2*14,90 + 1*14,90
    },
  );

  testWidgets('P — écran panier vide : message + retour Boutique', (t) async {
    await t.pumpWidget(_wrapCart(const CartScreen()));
    await t.pump();

    expect(find.text('Ton panier est vide'), findsOneWidget);
    expect(find.text('Commander'), findsNothing);
    expect(find.text('Découvrir la boutique'), findsOneWidget);
  });

  testWidgets('Q/R — « Commander » : indisponible proprement, aucun achat', (
    t,
  ) async {
    _cart.addProduct(kShopProducts.firstWhere((p) => p.id == 'amethyste'));
    await t.pumpWidget(_wrapCart(const CartScreen()));
    await t.pump();

    await t.tap(find.text('Commander'));
    await t.pumpAndSettle();

    expect(find.textContaining('paiement sera disponible'), findsOneWidget);
    expect(_cart.quantityFor('amethyste'), 1); // panier intact, rien consommé
  });

  testWidgets('N — Dashboard « Voir mes tirages » ouvre toujours '
      'BibliothequeScreen', (t) async {
    await t.pumpWidget(
      AuryelStateScope(
        state: _state(),
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );
    await t.pump();

    await t.ensureVisible(find.text('Voir mes tirages'));
    await t.tap(find.text('Voir mes tirages'));
    await t.pumpAndSettle();

    expect(find.byType(BibliothequeScreen), findsOneWidget);
  });

  testWidgets('O — BibliothequeScreen.showBackButton inchangé', (t) async {
    await t.pumpWidget(const MaterialApp(home: BibliothequeScreen()));
    await t.pump();
    expect(find.byTooltip('Retour'), findsNothing);

    await t.pumpWidget(
      const MaterialApp(home: BibliothequeScreen(showBackButton: true)),
    );
    await t.pump();
    expect(find.byTooltip('Retour'), findsOneWidget);
  });

  for (final w in const [360.0, 375.0, 384.0, 390.0, 430.0]) {
    testWidgets(
      'S — aucun overflow Boutique + fiche + panier à ${w.toInt()} dp',
      (t) async {
        t.view.devicePixelRatio = 1.0;
        t.view.physicalSize = Size(w, 3200);
        addTearDown(t.view.reset);

        await t.pumpWidget(_boutique());
        await t.pump();
        expect(t.takeException(), isNull, reason: 'Boutique ${w.toInt()} dp');

        await t.pumpWidget(
          _wrapCart(ProductDetailScreen(product: kShopProducts.first)),
        );
        await t.pump();
        expect(t.takeException(), isNull, reason: 'fiche ${w.toInt()} dp');

        _cart.addProduct(kShopProducts.first);
        _cart.addProduct(kShopProducts[2]);
        await t.pumpWidget(_wrapCart(const CartScreen()));
        await t.pump();
        expect(t.takeException(), isNull, reason: 'panier ${w.toInt()} dp');
      },
    );
  }
}
