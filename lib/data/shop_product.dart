import 'package:phosphor_icons/phosphor_icons.dart';

/// Boutique V1 — catégories de produits **physiques** uniquement (aucun contenu
/// numérique, aucune consultation / crédit / heure / abonnement / méditation
/// payante : ces achats in-app restent séparés du commerce physique).
enum ShopCategory {
  tarotOracles,
  bougiesRituels,
  pierresBienEtre,
  carnetsAccessoires,
}

extension ShopCategoryX on ShopCategory {
  String get label {
    switch (this) {
      case ShopCategory.tarotOracles:
        return 'Tarot & Oracles';
      case ShopCategory.bougiesRituels:
        return 'Bougies & rituels';
      case ShopCategory.pierresBienEtre:
        return 'Pierres & bien-être';
      case ShopCategory.carnetsAccessoires:
        return 'Carnets & accessoires';
    }
  }

  PhosphorIconData get icon {
    switch (this) {
      case ShopCategory.tarotOracles:
        return PhosphorIconsRegular.cardsThree;
      case ShopCategory.bougiesRituels:
        return PhosphorIconsRegular.flame;
      case ShopCategory.pierresBienEtre:
        return PhosphorIconsRegular.diamond;
      case ShopCategory.carnetsAccessoires:
        return PhosphorIconsRegular.notebook;
    }
  }
}

/// Un produit de la boutique.
///
/// ⚠️ V1 = **données de démonstration UI**. Ces produits ne sont pas encore
/// réellement vendus ni en stock. Les prix sont centralisés ici (jamais codés
/// dans les widgets) pour un remplacement trivial par une source distante.
class ShopProduct {
  const ShopProduct({
    required this.id,
    required this.name,
    required this.category,
    required this.priceCents,
    required this.shortDescription,
    this.imageAsset,
    this.featured = false,
    this.badge,
  });

  final String id;
  final String name;
  final ShopCategory category;

  /// Prix en centimes d'euro (démo). Formaté via [priceLabel].
  final int priceCents;
  final String shortDescription;

  /// Chemin d'un asset local si un visuel réel existe ; `null` -> placeholder
  /// DA Auryel. **Aucune image externe** en V1.
  final String? imageAsset;

  final bool featured;

  /// Petit libellé optionnel ("Sélection Auryel", "Nouveau"…).
  final String? badge;

  /// "24,90 €" — jamais de prix codé en dur côté widget.
  String get priceLabel => formatEuroCents(priceCents);
}

/// Format FR d'un montant en centimes : `2490` -> "24,90 €". Centralisé pour
/// le catalogue ET le panier (jamais de `double`, on reste en `int`).
String formatEuroCents(int cents) {
  final euros = cents ~/ 100;
  final rest = cents % 100;
  return '$euros,${rest.toString().padLeft(2, '0')} €';
}

/// Produit du catalogue par `id`, ou `null` si l'`id` est inconnu (catalogue
/// modifié entre deux versions -> le panier ignore proprement la ligne).
ShopProduct? shopProductByIdOrNull(String id) {
  for (final p in kShopProducts) {
    if (p.id == id) return p;
  }
  return null;
}

/// Catalogue de démonstration V1 (8 produits). À remplacer par une source
/// distante — **jamais dans ce lot** (pas d'API, pas de Shopify, pas de backend).
const List<ShopProduct> kShopProducts = [
  ShopProduct(
    id: 'tarot-marseille',
    name: 'Tarot de Marseille',
    category: ShopCategory.tarotOracles,
    priceCents: 2490,
    shortDescription:
        'Un jeu de 78 lames dans la tradition marseillaise, pour tes tirages.',
    featured: true,
    badge: 'Sélection Auryel',
  ),
  ShopProduct(
    id: 'oracle-introspectif',
    name: 'Oracle introspectif Auryel',
    category: ShopCategory.tarotOracles,
    priceCents: 2990,
    shortDescription:
        'Quarante cartes de questions et d’images pour ralentir et réfléchir.',
  ),
  ShopProduct(
    id: 'bougie-ambre-santal',
    name: 'Bougie Ambre & Santal',
    category: ShopCategory.bougiesRituels,
    priceCents: 1990,
    shortDescription:
        'Cire végétale, mèche coton, environ quarante heures de combustion.',
  ),
  ShopProduct(
    id: 'coffret-rituel-soir',
    name: 'Coffret Rituel du soir',
    category: ShopCategory.bougiesRituels,
    priceCents: 3990,
    shortDescription:
        'Bougie, encens et carte de rituel pour clore la journée en douceur.',
    featured: true,
  ),
  ShopProduct(
    id: 'amethyste',
    name: 'Améthyste',
    category: ShopCategory.pierresBienEtre,
    priceCents: 1490,
    shortDescription: 'Pierre brute d’améthyste, taille paume de main.',
  ),
  ShopProduct(
    id: 'quartz-rose',
    name: 'Quartz rose',
    category: ShopCategory.pierresBienEtre,
    priceCents: 1490,
    shortDescription: 'Galet de quartz rose poli, à garder près de soi.',
  ),
  ShopProduct(
    id: 'carnet-auryel',
    name: 'Carnet Auryel',
    category: ShopCategory.carnetsAccessoires,
    priceCents: 1990,
    shortDescription: 'Carnet cousu de cent vingt pages, papier ivoire, pour noter tes tirages.',
  ),
  ShopProduct(
    id: 'pochette-cartes',
    name: 'Pochette pour cartes',
    category: ShopCategory.carnetsAccessoires,
    priceCents: 2490,
    shortDescription: 'Étui en velours pour protéger ton jeu au quotidien.',
  ),
];
