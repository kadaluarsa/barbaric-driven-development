# Mutation Type Registry

Every D# **must** include a `reason:` field with exactly one registered mutation type.
The type code is the first word before ` — ` (space, em-dash, space).

The part after ` — ` is a human-readable description of what the mutant changes.

## Registered types

| Code | Meaning | Example |
|---|---|---|
| `REMOVED_GUARD` | Remove a guard clause or validation | `if balance < amount: raise` → removed |
| `INVERTED_CONDITION` | Invert a boolean condition | `if balance >= amount` → `if balance > amount` |
| `WRONG_CONSTANT` | Use wrong constant, limit, or threshold | `MAX_LIMIT = 100` → `MAX_LIMIT = 999999` |
| `SKIPPED_STEP` | Skip a required step in a flow | `verify_payment()` not called |
| `BYPASSED_AUTH` | Bypass an authorization or role check | `require_role('admin')` commented out |
| `WRONG_STATE` | Wrong state transition or status code | `status = PAID` instead of `status = PENDING` |
| `REMOVED_ENCRYPTION` | Skip encryption, hashing, or encoding | Data sent without cryptographic signature |
| `ALLOWED_OVERFLOW` | Allow buffer, index, or counter overflow | No bounds check on array access |

## Rules

1. **`reason:` must start with a registered type code.** The script compares the word before the first ` — ` against this table.
2. **One type per `reason:` line.** If multiple mutations would test the same law, write multiple D# entries.
3. **A type from a future version that is not in this table is invalid.** Add it here first, then use it.
4. **Legacy laws with no `reason:` are accepted** (backward compat) but `dsharp_strength.sh` skips validation for them.

## Adding a new type

1. Add the row to this table (both human-readable and machine-parsed section).
2. Add the type code to `VALID_MUTATION_TYPES` in `tests/dsharp_strength.sh`.
3. Add a test case to `tests/enforcement.sh` (new T#) that asserts the new type is recognised.
4. Sign and commit.
