# Decision & Assumptions Log — NEP Turbine Sensor Alert Triage

**Project:** Nordic EcoPower SEAP — Turbine Sensor Alert Triage
**Phase:** Intake
**Prepared on:** 2026-10-06
**Status:** Draft for approval

This log records decisions already made and assumptions being proceeded on. Open items that need a stakeholder answer are listed in §3 — none currently block intake, but the first should be verified before design begins.

---

## 1. Decisions Made

| ID | Decision | Rationale | Source / Decided by | Date |
|---|---|---|---|---|
| **DL-01** | **Both High and Critical readings escalate** (auto-create a Case in the Field Response Queue). | BR §6 ("any reading assessed as high severity must automatically and immediately trigger a response action") and the project one-liner both say High **and** Critical. The swimlane process map shows escalation only "if critical" — a **contradiction resolved in favour of BR §6**, which is the requirement of record. | Confirmed by user | 2026-10-06 |
| **DL-02** | **Unmatched readings are scored and escalated.** When a reading's turbine model cannot be matched, score it against the **UNMATCHED fallback thresholds (>90 °C / >45 Hz)**, **auto-create a Case if it scores High/Critical**, and **mark the record UNMATCHED** so it is easily identifiable for follow-up. | Data & Threshold Requirements v3 §2 defines UNMATCHED fallback values and requires marking the record; BR §1 requires unmatched readings stay visible, never silently dropped. User confirmed these readings escalate rather than being flagged for manual-only follow-up. | Confirmed by user | 2026-10-06 |
| **DL-03** | **Four Intake artifacts produced this turn:** Intake Summary / Project Brief, Decision & Assumptions Log, Stakeholder Map / RACI seed, Initial Risk & Dependency Register. | Scope agreed for the Intake phase (framing & ownership, not design). | Confirmed by user | 2026-10-06 |
| **DL-04** | **Gherkin acceptance scenarios for DL-01/DL-02 are not produced this turn.** | Offered as an add-on; declined for this Intake turn. Appropriate for the stories/design phase. | Confirmed by user (declined) | 2026-10-06 |
| **DL-05** | **Intake artifacts are written as Markdown (.md) under `Docs/` in the repo.** | Agreed output format for this deliverable. | Confirmed by user | 2026-10-06 |

## 2. Assumptions Being Proceeded On

These are stated so stakeholders can agree or correct them. A-01 is the one that most warrants verification before design.

| ID | Assumption | Basis | Risk if wrong | Verify by |
|---|---|---|---|---|
| **A-01** | `Asset.ExternalIdentifier` **exists on the connected org** and holds the unique turbine Id that matches the inbound sensor `TurbineId`. | Asserted in Data & Threshold Requirements v3 §1 and Assumptions & Constraints v5 §4. **Not verified against the org** — the org did not respond when checked at intake ("Salesforce connection record missing — reconnect"). | The entire matching mechanism — and therefore scoring, history and escalation — rests on this field. If absent or populated differently, the matching design changes materially. | Reconnect the org and confirm the field before/at the start of design. |
| **A-02** | `Asset.ExternalIdentifier` and `Asset.Model` **will be populated across the fleet by an existing integration**, assumed in place for go-live. | BR §8; Assumptions §4. | If the populating integration is not ready at go-live, matching has nothing to match against and readings default to UNMATCHED en masse. | Confirm the Asset-population integration's go-live readiness with NEP. |
| **A-03** | **No null/missing-field handling is required** — every inbound payload has all fields present and populated. | Data & Threshold Requirements v3 §1. | Real vendor data with gaps would break scoring if this holds only "for this exercise." | Confirm with NEP whether this holds for production data. |
| **A-04** | **Severity thresholds supplied are final, production-equivalent data** and the three named models (NEP-Legacy, NEP-Standard, NEP-NextGen) plus UNMATCHED cover the fleet. | Data & Threshold Requirements v3 §2. | Additional models in the fleet would need their own threshold rows; absent that, they fall to UNMATCHED fallback. | Confirm model coverage against the actual fleet list. |
| **A-05** | **Plain-language summaries will be deterministic** (Apex/Flow string construction from the severity assessment), reproducible from the same input every time. | Guidelines §4; Assumptions §7 — a real customer constraint, not a simplification. | None if honoured; a generative-AI shortcut would breach a hard constraint. | N/A — hard constraint, held. |
| **A-06** | The **SEAP-provisioned org is the target environment**, treated as production-equivalent; no CI/CD or sandbox strategy in scope. | Assumptions §2. | Expectation mismatch if NEP expects a managed release path. | Confirm with NEP. |
| **A-07** | **No business/target metrics are invented.** Figures used (€40k, 150–400+ emails/day, ~2–3 min/alert, 3–4× storm surge, "within minutes") are quoted from the customer's own documents; any committed numeric target is marked `[TBD]`. | C-Suite Brief; Discovery Transcript. | N/A — stated for transparency. | N/A |

## 3. Open Items (non-blocking for intake; settle in Discovery/Design)

| ID | Open item | Why it is deferred, not asked now | Owner to resolve |
|---|---|---|---|
| **O-01** | Verify `Asset.ExternalIdentifier` on the org (per A-01). | Mechanism-level; does not change the intake framing. The org was unreachable this turn. | Salesforce Architect + NEP admin |
| **O-02** | Committed response-time target for escalation ("within minutes" is directional). | A target to negotiate with stakeholders, not an intake fact; marked `[TBD]`. | VP Operations + delivery lead |
| **O-03** | Field Response Queue **membership**. | Explicitly determined later, outside this project (BR §6). | NEP Operations |
| **O-04** | Exception-logging pattern beyond the baseline `NEP_IntegrationLog__c`. | Assumptions §5 invites alternative patterns as a **design conversation**, but it must not block build. | Salesforce Architect |
| **O-05** | Whether reporting/dashboards (Lars's operational health view and before/after executive view) become a later phase. | Explicitly out of scope this release (Assumptions §8); captured as a known future desire. | VP Operations + delivery lead |

---

### Sources
- C-Suite Brief.docx (Artifact)
- Business Requirements v6.docx (Artifact)
- Discovery Transcript v2.docx (Artifact)
- NEP_Sensor_Triage_Data_and_Threshold_Requirements_v3.docx (Artifact)
- Nordic EcoPower - Development & Design Guidelines v6.docx (Artifact)
- Nordic_EcoPower_Project_Assumptions_and_constraints_v5.docx (Artifact)
- NEP_swimlane_process_map.png (Artifact)
