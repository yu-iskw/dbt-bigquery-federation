# Full-codebase quality loop

Goal: Repeat `/simplify` → `/thermos` → address issues → `/verifier` across the **entire** codebase until reviewers report no remaining issues.

## Loop 1

- [x] `/simplify` whole-codebase review (quality, reuse, efficiency)
- [ ] `/thermos` whole-codebase review (bugs/security + code quality)
- [x] Address actionable simplify findings (planner unification, STRUCT/udt_name, ops reuse, harness)
- [ ] `/verifier` (`make lint`, unit tests, integration tests)
- [ ] Re-run reviews until clean
