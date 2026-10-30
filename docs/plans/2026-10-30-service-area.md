# Area editing and normalization

Owner: current chat. Baseline: developer 8583cb4. Approved scope: native Site/Floor area editing, explicit meter service area, deduplicated statistical area, frozen report/export basis. No deployment or user-history mutation.

1. Add native area-only save with admin/read/write checks, optimistic revision, positive finite m² values and a strict field whitelist. Native identity and tree remain read-only. Make FIN area authoritative over old overlays.
2. Persist explicit meter area source and service-space Ref; retain legacy custom numbers. Add Chinese/English editing controls and current-area preview.
3. In isolated calculation worktree, resolve row and selection denominators consistently, deduplicate same/contained spaces, reject ambiguous custom unions, and preserve base consumption in frozen areaBasis.
4. Render and export the frozen numerator, denominator, sources and result. Verify actual saved export content, Chinese/English UI, relevant Fantom tests, type checking and builds. Use isolated fixtures for native-save acceptance when practical; do not claim production verification.

Acceptance: 120+180 kWh serving one 1000 m² floor yields 0.30 kWh/m²; parent Site and Floor area is not counted twice; independent floors sum; multiple unknown custom boundaries have no combined intensity; missing area preserves absolute consumption. New native saves modify only area on the original FIN record and reject stale/unauthorized/structural writes.

## Delivery evidence, 2026-10-30

- Calculation c58dfd1 integrated as df68e2d1; final integration additionally covers per-energy denominators, malformed optional area references and native coverage placeholders.
- Full Fantom: 49 classes, 424 methods, 2882 assertions passed. Frontend: 38 files / 304 tests passed; final area/i18n/export/quality follow-up 40 passed. TypeScript, Vite and FIN 5.3.0.2761 Pod build passed. Version manifests remain 0.12.21; this is unshipped developer work.
- Final four Chinese/English desktop/mobile browser flows passed together, including actual downloaded Excel contents and later configuration changes that cannot alter the frozen result. Screenshots use controlled transport fixtures, not FIN business data. Evidence: out/service-area-browser/.
- Registered isolated native FIN: area save/readback/clear and rejected stale/forged/zero writes, 10 checks, audit e6490763-eb20-427a-801e-209b3c750edd. Reader writes rejected, audit a1127a22-9e07-4600-9cbe-6ae5e38a9b4e. Cleanup found zero fixture Sites/Floors, audit 1bd52ddc-6f33-449a-aea9-3b444fdd39ff. No history writes. Test instance stopped and original Pod restored by hash; main FIN untouched.
- Native-tested Pod SHA256: 07a4bff431fc17f0f1af88d2d2c924003a521a8c7f6fdd4b92add8a510189a78. Final local build: 2c64f0adafd36b58b8d4ae68b25e2547825449b5e741cf4fc8e3f9405551c9a6, with a later UI-only missing-service-space label guard. Backend code is unchanged from native acceptance. Final package is not deployed to cubeTest.
- FIN Expert connector checker treats raw Fantom as JSON and lacks a verified 5.3 profile; it supplies no pass evidence. Actual compilation, executable tests and native acceptance above supply the evidence.

Usage: Settings → Metering assets → Space → Edit area. Meter properties → Area source → Use a service space area / Custom service area. Native structure remains managed by FIN. Area basis follows the chart; Excel, PDF/print and Word use the frozen basis.
