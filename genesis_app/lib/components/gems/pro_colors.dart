import 'package:flutter/material.dart';

const proBurgundy = Color(0xFF701429);
const proGold = Color(0xFFD8B568);
const proLightGold = Color(0xFFF5DFA3);
const proGoldInk = Color(0xFFA0782C);
const proPurchaseAccent = proGold;
final proPurchaseTint = proGold.withValues(alpha: 0.12);
const proPurchaseInk = Color(0xFF38240D);
const proCopperAccent = Color(0xFFD94E3B);
const proPurchaseButtonGradient = LinearGradient(
  colors: [
    Color(0xFFC79236),
    Color(0xFFE5BA61),
    Color(0xFFFFF0B1),
    Color(0xFFE5BA61),
    Color(0xFFC79236),
  ],
  stops: [0, 0.26, 0.52, 0.78, 1],
);

// --- Profile 9k / 9k2 (design-0910) -------------------------------------
// Values taken verbatim from `export/profile-cards.dc.html`.

/// Card ground for the membership entry, `linear-gradient(104deg, ...)`.
const proCardGradient = LinearGradient(
  begin: Alignment(-0.94, -0.35),
  end: Alignment(0.94, 0.35),
  colors: [Color(0xFF3E2C0C), Color(0xFF6B4C12), Color(0xFF4A3410)],
  stops: [0, 0.52, 1],
);

/// Gold sweep clipped to the "Worldo Premium" wordmark.
const proTitleGradient = LinearGradient(
  colors: [
    Color(0xFFFBCB5C),
    Color(0xFFFDE293),
    Color(0xFFFEF9D1),
    Color(0xFFFDE293),
    Color(0xFFFBCB5C),
  ],
  stops: [0, 0.3, 0.5, 0.7, 1],
);

const proCardBody = Color(0xFFF0DDB2);
const proCardBodyStrong = Color(0xFFFFF2D2);
const proSubscribeFill = Color(0xFFF3C558);
const proSubscribeInk = Color(0xFF42290A);
const proActiveTagFill = Color(0x33FFD98A);
const proActiveTagInk = Color(0xFFFFD98A);

/// Ground for the two-balance gems entry.
const gemsCardFill = Color(0xFF232228);
const gemsCardDivider = Color(0x1FFFFFFF);
const gemsCardLabel = Color(0x80FFFFFF);

/// The wordmark's gold sweep, re-anchored on the Subscribe fill so a button
/// filled with it still reads as the same gold. Left-to-right, brightest mid.
const proButtonGradient = LinearGradient(
  colors: [
    Color(0xFFE8B843),
    proSubscribeFill,
    Color(0xFFFDE9A8),
    proSubscribeFill,
    Color(0xFFE8B843),
  ],
  stops: [0, 0.28, 0.5, 0.72, 1],
);
