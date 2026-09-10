# Wallet Subscription design QA

final result: passed

## Target and evidence

- Source: `/var/folders/yq/n40lcvz566z_9v85h4rj2fl00000gn/T/codex-clipboard-650153d5-81b6-4f9e-a9ff-bc8ed5c24d5c.jpg`, 1080 × 2336 pixels.
- Native Flutter captures: `build/ui_previews/subscription/yearly.png`, `monthly.png`, `benefits-scrolled.png` (428 × 926), and `small.png` (320 × 568).
- 428 × 926 logical viewport corresponds to the supplied iPhone 13 Pro Max reference. Capture DPR 1; safe areas 47 top / 34 bottom. Source interpreted at 428 / 1080 scale. Captures use embedded Inter/Inter Italic and Material icon fonts.
- These are actual Flutter widget renders, not installed-device or browser captures. System status-bar artwork is omitted. Source and implementation were viewed together; control and text details are readable at 1× without separate crops.
- User's requested adaptation: retain Buy Gems white surfaces, subtle borders, 8px radii and brand red while matching the screenshot's subscription structure. One Pro tier, two billing periods, approved demo prices/benefits; no subscription/payment integration.

## Iterations and resolved findings

1. First draft put the introduction inside the scroll view, used an oversized headline, an undersized CTA label, a medal instead of a crown, and an inset discount badge. Corrected to fixed introduction + fixed Pro card heading + scrolling benefits only + fixed purchase controls. The headline is now 18px, CTA 18px/w700, crown appears in the Subscription tab, and the discount badge overlaps the yearly card's top-left border by 9px.
2. Added page-centered header title placement independent of the back and Records widths. Tests assert exact center at widths 428, 390 and 320.
3. Converted the colorful Gems illustration to a monochrome diamond icon. All benefit icons are single-color. User-requested demo status states are red solid upward arrow (improved over free), black check (same as free), gray lock and gray text (higher tier required). No additional paid tier was introduced.
4. The library crown was still missing the reference details. Enlarged the supplied crown/up reference regions and redrew dedicated SVGs: the crown now has a round top, stepped shoulders, sloped sides and left inner stroke; the upgrade icon is a filled upward arrow with a short stem-width motion bar. The library crown/license was removed. Focused reference crops are `build/ui_previews/subscription/reference-crown.jpg` and `reference-up.jpg`; compared with the final full-page render in the same image input.
5. Narrow-screen test found legal-label overflow with test fallback fonts; flexible footer labels fix it. Final render and tests report no subscription layout exceptions.
6. Final native captures verify yearly/monthly selection, top-of-list and scrolled benefits, fixed header/CTA, badge overlap and narrow viewport layout. No remaining P0/P1/P2 findings in the requested flow.

## Final visual parameters

- Header: existing 50px height, centered tab group up to 260px wide; 14px/w600 tab text and 22px crown slot. Selected text/crown #111111; unselected #666666.
- Introduction: 18px/w700 headline; 14px secondary copy. Pro heading: 28px/w700 using shared Inter Italic handling.
- Benefits: 14px text, 28px icon surfaces, 20px monochrome glyphs. Upgrade uses the dedicated `upgrade.svg`. Red arrows #FF2442, checks #111111, locks #999999.
- Plans: 92px height, 20px horizontal gap, 14px regular period label, 24px regular price, 14px `/mo` suffix.
- Savings badge: 21px high, 11px text, x aligned with yearly card, top −9px. Red background with small yellow flame.
- CTA: 44px high, 18px/w700 Inter, brand red; 34px gap after plans.
- Assets: existing app SVGs, Material icons, and crown/upgrade SVGs redrawn from the supplied reference. No raster art needed for the light Buy Gems style.

## Verification and limits

- After the icon/tab corrections, all 32 Wallet tests and the temporary rendered capture test passed.
- Targeted `flutter analyze` passes for all changed Dart source and Wallet tests.
- Wallet tests cover fixed regions while benefits scroll, all three status meanings/colors, exact tab centering, discount badge overlap, plan and list preservation, offline Gems data, narrow layout, and existing Gems purchase/task flows.
- Temporary native capture test passed and was removed after saving artifacts.
- Broad `test/ui/genesis_ui_test.dart` additionally exposes two failures outside the subscription widgets: existing component-theme icon color expectation (line 177) and Samsung gesture-mode detection expectation (line 1283). Neither affected source component was changed; these remain unresolved, and the broad suite is not reported as passing.
- Subscription products/entitlements and actual store purchasing remain unimplemented as requested. No installed-device verification.

Implementation checklist: complete for the frontend demo. Replace demo benefits/prices when finalized.
