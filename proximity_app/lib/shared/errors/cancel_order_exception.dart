/// Sprint 12 -- thrown by both `CheckoutRepository.cancelOrder` (buyer) and
/// `ShopOrdersRepository.cancelOrder` (shop) -- one shared type for one
/// backend RPC (rpc_cancel_order, migrations/047) reached from two
/// different features, rather than two repositories each defining their own
/// near-identical exception class. Lives in `shared/` rather than either
/// feature's own `data/` folder specifically so neither feature has to
/// import the other's repository file just to catch this.
class CancelOrderException implements Exception {
  CancelOrderException(this.code, this.message);

  final String code;
  final String message;
}
