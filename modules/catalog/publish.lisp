;;;; modules/catalog/publish.lisp -- what the catalog module publishes to
;;;; clients, and its seal.

(in-package #:tun.catalog)

(publish '(product product-name product-kind product-unit product-unit-price-minor
           product-stock-tracked product-units-owned product-revision product-article-id
           product-department product-requirements product-lite-requirement-id
           find-product rental-product-p consumable-product-p stock-tracked-consumable-p
           products-create products-get products-list products-update products-transfer
           recipe choice-group catalog-change set-lite-recipe
           recipes-create recipes-update recipes-get recipes-list recipes-archive
           choice-groups-create choice-groups-update choice-groups-get choice-groups-list choice-groups-archive
           catalog-changes-list products-set-requirements))

(seal-module "catalog")
