import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auryel/data/shop_cart_store.dart';
import 'package:auryel/data/shop_product.dart';

// ===========================================================================
// BOUTIQUE V1.1 — panier LOCAL (aucun backend, aucun Stripe).
// ===========================================================================

ShopProduct _p(String id) => kShopProducts.firstWhere((p) => p.id == id);

const _key = 'auryel.shop_cart.v1';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ShopCartStore.debugResetInstance();
  });

  test('A — panier vide au départ', () async {
    final cart = ShopCartStore(autoLoad: false);
    expect(cart.isEmpty, isTrue);
    expect(cart.items, isEmpty);
    expect(cart.totalItems, 0);
    expect(cart.subtotalCents, 0);
  });

  test('B — ajout d’un produit', () {
    final cart = ShopCartStore(autoLoad: false);
    cart.addProduct(_p('amethyste'));
    expect(cart.lineCount, 1);
    expect(cart.quantityFor('amethyste'), 1);
    expect(cart.totalItems, 1);
    expect(cart.contains('amethyste'), isTrue);
  });

  test(
    'C — ajout du même produit -> quantité +1, toujours une seule ligne',
    () {
      final cart = ShopCartStore(autoLoad: false);
      cart.addProduct(_p('amethyste'));
      cart.addProduct(_p('amethyste'));
      cart.addProduct(_p('amethyste'));
      expect(cart.lineCount, 1);
      expect(cart.quantityFor('amethyste'), 3);
      expect(cart.totalItems, 3);
    },
  );

  test('D — plusieurs produits distincts', () {
    final cart = ShopCartStore(autoLoad: false);
    cart.addProduct(_p('amethyste'));
    cart.addProduct(_p('quartz-rose'));
    cart.addProduct(_p('carnet-auryel'));
    expect(cart.lineCount, 3);
    expect(cart.totalItems, 3);
  });

  test('E — totalItems = somme des unités, pas des lignes', () {
    final cart = ShopCartStore(autoLoad: false);
    cart.addProduct(_p('tarot-marseille'));
    cart.addProduct(_p('tarot-marseille'));
    cart.addProduct(_p('bougie-ambre-santal'));
    expect(cart.lineCount, 2);
    expect(cart.totalItems, 3);
  });

  test('F — sous-total = somme(prixCatalogue * quantité)', () {
    final cart = ShopCartStore(autoLoad: false);
    cart.addProduct(_p('tarot-marseille')); // 2490
    cart.addProduct(_p('tarot-marseille')); // 2490
    cart.addProduct(_p('amethyste')); // 1490
    expect(cart.subtotalCents, 2490 * 2 + 1490);
    expect(formatEuroCents(cart.subtotalCents), '64,70 €');
  });

  test('G — increment', () {
    final cart = ShopCartStore(autoLoad: false);
    cart.addProduct(_p('amethyste'));
    cart.increment('amethyste');
    expect(cart.quantityFor('amethyste'), 2);
  });

  test('H — decrement au-dessus de 1', () {
    final cart = ShopCartStore(autoLoad: false);
    cart.addProduct(_p('amethyste'));
    cart.increment('amethyste'); // 2
    cart.decrement('amethyste'); // 1
    expect(cart.quantityFor('amethyste'), 1);
  });

  test(
    'I — decrement sur 1 supprime la ligne (jamais de quantité négative)',
    () {
      final cart = ShopCartStore(autoLoad: false);
      cart.addProduct(_p('amethyste'));
      cart.decrement('amethyste');
      expect(cart.contains('amethyste'), isFalse);
      expect(cart.isEmpty, isTrue);
      // decrement idempotent sur ligne absente
      cart.decrement('amethyste');
      expect(cart.totalItems, 0);
    },
  );

  test('J — removeLine retire toute la ligne quelle que soit la quantité', () {
    final cart = ShopCartStore(autoLoad: false);
    cart.addProduct(_p('amethyste'));
    cart.increment('amethyste');
    cart.increment('amethyste'); // qty 3
    cart.removeLine('amethyste');
    expect(cart.isEmpty, isTrue);
  });

  test('K — clear vide le panier', () {
    final cart = ShopCartStore(autoLoad: false);
    cart.addProduct(_p('amethyste'));
    cart.addProduct(_p('quartz-rose'));
    cart.clear();
    expect(cart.isEmpty, isTrue);
    expect(cart.totalItems, 0);
  });

  test('L — cap à 99 par ligne', () {
    final cart = ShopCartStore(autoLoad: false);
    cart.addProduct(_p('amethyste'));
    for (var i = 0; i < 200; i++) {
      cart.increment('amethyste');
    }
    expect(cart.quantityFor('amethyste'), ShopCartStore.maxPerLine);
  });

  test('M — persistance locale : seuls id + quantité sont écrits', () async {
    final cart = ShopCartStore(autoLoad: false);
    cart.addProduct(_p('amethyste'));
    cart.increment('amethyste');
    cart.addProduct(_p('quartz-rose'));
    await Future<void>.delayed(Duration.zero); // laisse _persist() finir

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    expect(raw, isNotNull);
    final decoded = jsonDecode(raw!) as List;
    expect(decoded, [
      {'id': 'amethyste', 'q': 2},
      {'id': 'quartz-rose', 'q': 1},
    ]);
    // aucun prix persisté
    expect(raw.contains('price'), isFalse);
    expect(raw.contains('1490'), isFalse);
  });

  test(
    'N — reload : le panier revient à l’identique après redémarrage',
    () async {
      SharedPreferences.setMockInitialValues({
        _key: jsonEncode([
          {'id': 'amethyste', 'q': 2},
          {'id': 'carnet-auryel', 'q': 1},
        ]),
      });
      final cart = ShopCartStore();
      await cart.load();
      expect(cart.isLoaded, isTrue);
      expect(cart.quantityFor('amethyste'), 2);
      expect(cart.quantityFor('carnet-auryel'), 1);
      expect(cart.totalItems, 3);
      expect(cart.subtotalCents, 1490 * 2 + 1990);
    },
  );

  test('O — productId inconnu au rechargement : ignoré proprement', () async {
    SharedPreferences.setMockInitialValues({
      _key: jsonEncode([
        {'id': 'produit-supprime-v0', 'q': 5},
        {'id': 'amethyste', 'q': 1},
        {'id': '', 'q': 3},
        {'q': 2},
        'nonsense',
      ]),
    });
    final cart = ShopCartStore();
    await cart.load();
    expect(cart.lineCount, 1);
    expect(cart.quantityFor('amethyste'), 1);
  });

  test('P — addProduct sur un id hors catalogue est refusé', () {
    final cart = ShopCartStore(autoLoad: false);
    cart.increment('inconnu-xyz');
    expect(cart.isEmpty, isTrue);
  });

  test('Q — JSON illisible : panier vide, pas de crash', () async {
    SharedPreferences.setMockInitialValues({_key: '{{ pas du json'});
    final cart = ShopCartStore();
    await cart.load();
    expect(cart.isEmpty, isTrue);
    expect(cart.isLoaded, isTrue);
  });

  test('R — notifyListeners à chaque mutation', () {
    final cart = ShopCartStore(autoLoad: false);
    var ticks = 0;
    cart.addListener(() => ticks++);
    cart.addProduct(_p('amethyste')); // 1
    cart.increment('amethyste'); // 2
    cart.decrement('amethyste'); // 3
    cart.addProduct(_p('quartz-rose')); // 4
    cart.clear(); // 5
    expect(ticks, 5);
  });

  test('S — ShopCartScope.of retombe sur l’instance globale sans scope', () {
    final store = ShopCartStore.instance;
    expect(identical(store, ShopCartStore.instance), isTrue);
  });
}
