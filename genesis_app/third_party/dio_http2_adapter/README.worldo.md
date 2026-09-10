# Worldo local patch

Based on dio_http2_adapter 2.8.0 from the locked pub package. Library files and
LICENSE are retained; unused upstream dev dependencies are omitted.

The only runtime change is in `_throwIfH2NotSelected`: destroy the unpooled TLS
socket before signalling HTTP/1.1 fallback. Successful HTTP/2 connections,
certificate validation, request bodies, and retry behavior are unchanged.

Regression: `test/network/dio_http_fallback_integration_test.dart` checks actual
HTTP/1.1 POST counts and server-side open connections after repeated fallback.
Remove this override when an upstream version includes the same cleanup, after
rerunning the transport and Gateway regression suites.
