;;;; modules/inventory/publish.lisp -- what the inventory module publishes to
;;;; clients, and its seal.

(in-package #:tun.inventory)

(publish '(on-hand reserved-quantity article
           articles-create articles-get articles-list articles-update articles-archive articles-recount
           articles-transfer transfers-list
           inventory-receive inventory-adjust inventory-balance inventory-movements
           inventory-shortages inventory-forecast inventory-purchase-suggestions inventory-availability-grid
           purchase-suggestions))

(seal-module "inventory")
