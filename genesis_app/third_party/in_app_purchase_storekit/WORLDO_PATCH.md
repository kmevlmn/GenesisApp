# Worldo StoreKit patch

Based on Flutter `in_app_purchase_storekit` 0.4.11+2 (BSD license in LICENSE).
Runtime and Pigeon sources are vendored at the resolved version; platform result
delivery, transaction verification, and transaction finishing retain upstream behavior.

The optional `Sk2PurchaseParam.onStoreHandoff` callback runs after native product
lookup and unfinished-transaction checks, immediately before `Product.purchase`.
A per-call `handoffId` travels in purchase options and a method-channel handshake
asks the owning checkout to proceed. False, unknown, or expired callbacks prevent
launch. The id is local IPC metadata, never an App Store option or backend field.

The callback means control is handed to StoreKit; Apple does not supply a separate
confirmation-sheet-visible callback here. The purchase Future still returns its
original result after user interaction. The app must not apply its preparation
deadline during that interaction.

Pigeon source and both generated purchase-option codecs include the trailing
optional `handoffId`; regenerate both together when updating upstream.
