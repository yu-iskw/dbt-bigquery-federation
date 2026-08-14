# Full-codebase quality loop

Goal: Repeat `/simplify` → `/thermos` → address issues → `/verifier` across the **entire** codebase until reviewers report no remaining high-conviction issues.

## Loop 1

- [x] `/simplify` whole-codebase review (quality, reuse, efficiency)
- [x] `/thermos` whole-codebase review (bugs/security + code quality)
- [x] Address actionable findings (planner unification, STRUCT/udt_name, pinned projection, Spanner quotes, ops reuse)
- [x] `/verifier` (lint except blocked external links; unit 1.10/1.11; integration 1.11)

## Loop 2

- [x] Re-review remaining defects
- [x] ARRAY udt_name restriction, pin/diff declared type, shared GoogleSQL quoter
- [ ] Confirm thermos loop-2 has no remaining High issues
