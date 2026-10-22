# Round 10 — Create-account wizard

Status: **Done 2026-10-22.** Backend 65/65 (new `test/create_wizard.test.js`); Flutter analyze clean; 198 Flutter tests pass, 5 skipped (new `test/create_wizard_test.dart`, wizards added to the layout sweep at 360, 768 and 1024 px). Checklist: `LIQo backend/docs/TESTING.md`, "Round 10".

## Request
"When I create an account, I want a wizard style setup so that I am aware of how many steps I shall take, and show me immediately if an email or another thing that shall not be duplicated has another match, and other edge cases." The owner asked to be interviewed where unclear.

## What the system did before
- Four create paths: superadmin "Create account", mall owner "Create mall admin", "Create new" owner or admin on a mall page, mall admin "Add store owner" (Store owners page and a store's page). The first three used two dialogs in a row ("Step 1 of 2"); the store-owner one was a single dialog.
- The email was checked only when the server received the final submit. Names could repeat with no hint.
- Creating an account ignored emails waiting in someone's profile change request (that request then failed at approval).
- A branch could already have several mall admins; nothing said so.
- An inactive store owner's email silently reactivated them and added the store.

## Owner decisions (interview, 2026-10-22)
| Question | Decision |
|---|---|
| Which flows | All four create paths. |
| Format | A dialog with a step bar. |
| Steps | Role, Details, Access, Review, then Done. Superadmins skip Access; a fixed role skips Role. |
| Email already used | Details (name, role, a link to open it) for a superadmin only; others see "already in use". |
| Email of an inactive account | Block, with a link to open it (superadmin). |
| Email waiting in a profile change request | Allow, with a warning. |
| Same full name | Warn, allow. Others than the superadmin see no role. |
| Store owner email already a store owner | Add the store to them; say so right away; no new password. |
| Same, but the store owner is inactive | Block, like other inactive accounts. Reactivate from Store owners first. |
| Store-owner steps | Store, Details, Review, Done (Store skipped on a store's page). |
| Branch already has a mall admin | Show who, allow. |
| When checks run | While typing, about half a second after typing stops. Next stays off while checking or blocked. |
| Closing after typing | Ask "Discard this account?". |
| Creating a superadmin | Warning on Role and Review, plus the existing confirmation on Create. |
| Temporary password | On the wizard's last step, Done, with Copy and "Open account". |

## What was built
- **Backend** `GET /accounts/check` (superadmin, mall owner, mall admin): `email` (`free`, `taken`, `inactive`, `pending_request`, `store_owner`, `invalid`; holder details only for a superadmin, or a store owner to a mall admin in the store-owner wizard), `fullName` (count; matches only for a superadmin), `branchId` (admins already there, scope-checked). New repo queries `users.findByFullName`, `assignments.branchAdmins`. `POST /owners` refuses an inactive store owner (409). `POST /accounts` says "inactive account" when that is why the email is refused.
- **Shared** `shared/forms/wizard_dialog.dart`: `WizardFrame` (title, close, step bar, "STEP 2 OF 5", heading, scrolling body, error, buttons), `WizardStepBar`, `CheckNote` (checking, ok, info, warn, block, with an optional action), `WizardButton`, `ChoiceCard`, `WizardOutcome`. `FieldBuilder` gained a `note` slot. `OneTimeSecretBox` is reusable.
- **Accounts** `features/accounts/create_account_wizard.dart` (replaces `create_account_flow.dart`), `account_checks.dart` (check service, debounced `LiveCheck`, the wording of each result). `assignment_dialog.dart` split into `AssignmentFields` (used by the wizard's Access step) and the existing Assignments dialog.
- **Stores** `features/stores/store_owner_wizard.dart`, used by the Store owners page and a store's "Add owner".
- If the email is taken between the check and Create, the wizard returns to Details with the server's message under the email. Access errors (for example an owner who does not cover the branch) return to Access.

## Not changed
- A branch may still have several mall admins.
- Account roles still cannot be changed after creation (open from the superadmin review).
