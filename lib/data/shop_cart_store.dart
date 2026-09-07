import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shop_product.dart';

/// Une ligne de panier : un produit + une quantité.
///
/// ⚠️ On ne persiste QUE [productId] et [quantity]. Le prix n'est jamais
/// stocké comme vérité : il est re-résolu depuis [kShopProducts] au
/// rechargement, et le futur Stripe Checkout recalculera toujours le vrai
/// montant côté backend.
class CartItem {
  const CartItem({required this.productId, required this.quantity});

  final String productId;
  final int quantity;

  CartItem copyWith({int? quantity}) =>
      CartItem(productId: productId, quantity: quantity ?? this.quantity);

  Map<String, Object> toJson() => {'id': productId, 'q': quantity};

  static CartItem? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final q = raw['q'];
    if (id is! String || id.isEmpty) return null;
    final qty = q is int ? q : int.tryParse('$q') ?? 0;
    if (qty <= 0) return null;
    return CartItem(productId: id, quantity: qty);
  }
}

/// Panier LOCAL de la boutique (V1.1).
///
/// - Purement local (`SharedPreferences`), aucun backend, aucun Stripe.
/// - Survit au changement d'onglet, à la fermeture de l'app et au redémarrage.
/// - Les prix affichés viennent de [ShopProduct] UNIQUEMENT pour l'UX. Le
///   paiement réel (prochain lot) partira des `productId` + quantités, et le
///   backend restera seule source de vérité du montant.
class ShopCartStore extends ChangeNotifier {
  ShopCartStore({SharedPreferences? prefs, bool autoLoad = true})
    : _injected = prefs {
    if (autoLoad) {
      // ignore: discarded_futures
      load();
    }
  }

  static const _key = 'auryel.shop_cart.v1';

  /// Borne haute raisonnable par ligne (garde-fou UX, jamais négatif).
  static const int maxPerLine = 99;

  final SharedPreferences? _injected;
  Future<SharedPreferences> get _prefs async =>
      _injected ?? await SharedPreferences.getInstance();

  final List<CartItem> _lines = [];
  bool _loaded = false;

  /// Instance globale par défaut (écrans montés sans [ShopCartScope]).
  static ShopCartStore? _instance;
  static ShopCartStore get instance => _instance ??= ShopCartStore();

  /// Tests : repart d'un panier neuf (à appeler dans un `setUp`).
  @visibleForTesting
  static void debugResetInstance() {
    _instance?.dispose();
    _instance = null;
  }

  /// `true` une fois la lecture disque terminée.
  bool get isLoaded => _loaded;

  /// Lignes du panier (copie non modifiable), dans l'ordre d'ajout.
  List<CartItem> get items => List.unmodifiable(_lines);

  /// Nombre TOTAL d'unités (2 tarot + 1 bougie -> 3), pas le nombre de lignes.
  int get totalItems => _lines.fold(0, (sum, l) => sum + l.quantity);

  /// Nombre de lignes distinctes.
  int get lineCount => _lines.length;

  bool get isEmpty => _lines.isEmpty;

  /// Sous-total en centimes : somme(prixCatalogue * quantité). Un `productId`
  /// absent du catalogue compte pour 0 (il a normalement déjà été purgé).
  int get subtotalCents {
    var cents = 0;
    for (final l in _lines) {
      final p = shopProductByIdOrNull(l.productId);
      if (p != null) cents += p.priceCents * l.quantity;
    }
    return cents;
  }

  int quantityFor(String productId) {
    for (final l in _lines) {
      if (l.productId == productId) return l.quantity;
    }
    return 0;
  }

  bool contains(String productId) => quantityFor(productId) > 0;

  int _indexOf(String productId) =>
      _lines.indexWhere((l) => l.productId == productId);

  /// Ajoute [product] : nouvelle ligne (quantité 1) ou +1 si déjà présent.
  void addProduct(ShopProduct product) => _bump(product.id, 1);

  void increment(String productId) => _bump(productId, 1);

  /// -1 sur la quantité. Sur 1 -> la ligne est retirée (choix produit V1.1).
  void decrement(String productId) => _bump(productId, -1);

  void _bump(String productId, int delta) {
    final i = _indexOf(productId);
    if (i < 0) {
      if (delta <= 0) return;
      // On n'ajoute que des produits réellement au catalogue.
      if (shopProductByIdOrNull(productId) == null) return;
      _lines.add(CartItem(productId: productId, quantity: 1));
    } else {
      final next = _lines[i].quantity + delta;
      if (next <= 0) {
        _lines.removeAt(i);
      } else {
        _lines[i] = _lines[i].copyWith(
          quantity: next > maxPerLine ? maxPerLine : next,
        );
      }
    }
    _persistAndNotify();
  }

  /// Retire complètement la ligne (bouton corbeille).
  void removeLine(String productId) {
    final i = _indexOf(productId);
    if (i < 0) return;
    _lines.removeAt(i);
    _persistAndNotify();
  }

  /// Vide le panier.
  void clear() {
    if (_lines.isEmpty) return;
    _lines.clear();
    _persistAndNotify();
  }

  /// Charge le panier depuis le disque. Les `productId` inconnus (catalogue
  /// modifié) sont ignorés proprement. Les quantités sont fusionnées / bornées.
  Future<void> load() async {
    try {
      final prefs = await _prefs;
      final raw = prefs.getString(_key);
      _lines.clear();
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final entry in decoded) {
            final item = CartItem.tryFromJson(entry);
            if (item == null) continue;
            if (shopProductByIdOrNull(item.productId) == null) continue;
            final existing = _indexOf(item.productId);
            if (existing >= 0) {
              final merged = (_lines[existing].quantity + item.quantity).clamp(
                1,
                maxPerLine,
              );
              _lines[existing] = _lines[existing].copyWith(quantity: merged);
            } else {
              _lines.add(
                item.copyWith(quantity: item.quantity.clamp(1, maxPerLine)),
              );
            }
          }
        }
      }
    } catch (_) {
      _lines.clear();
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  void _persistAndNotify() {
    notifyListeners();
    // ignore: discarded_futures
    _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await _prefs;
      await prefs.setString(
        _key,
        jsonEncode(_lines.map((l) => l.toJson()).toList()),
      );
    } catch (_) {
      /* best-effort : le panier reste correct en mémoire */
    }
  }
}

/// Fournit un [ShopCartStore] à l'arbre (rebuild sur `notifyListeners`).
/// Sans scope dans l'arbre, `.of` retombe sur [ShopCartStore.instance] pour
/// que les écrans montés isolément (tests hérités) fonctionnent quand même.
class ShopCartScope extends InheritedNotifier<ShopCartStore> {
  const ShopCartScope({
    super.key,
    required ShopCartStore store,
    required super.child,
  }) : super(notifier: store);

  static ShopCartStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ShopCartScope>();
    return scope?.notifier ?? ShopCartStore.instance;
  }
}
