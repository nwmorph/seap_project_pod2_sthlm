# Initial Risk & Dependency Register — NEP Turbine Sensor Alert Triage

**Project:** Nordic EcoPower SEAP — Turbine Sensor Alert Triage
**Phase:** Intake
**Prepared on:** 2026-10-06
**Status:** Draft for approval

Initial register seeded from the eight source documents. Likelihood/Impact are **relative** (H/M/L) first-pass judgments for prioritisation, to be re-scored in Discovery. No invented metrics.

---

## 1. Risks

| ID | Risk | Likelihood | Impact | Priority | Mitigation / response | Source |
|---|---|---|---|---|---|---|
| **R-01** | **`Asset.ExternalIdentifier` is absent or behaves differently** from the documents' assertion. The entire matching mechanism — and all downstream scoring, history and escalation — depends on it. The org did not respond when checked at intake. | Medium | High | **High** | Reconnect the org and verify the field at the start of Discovery/design (O-01). Treat as a design gate — do not proceed with the matching design until confirmed. | A-01; Data & Threshold Reqs v3 §1; Assumptions §4 |
| **R-02** | **Hard storm-season deadline (~2 months)** with design, build and test all required beforehand, against a changing fleet and configurable logic. | Medium | High | **High** | Phase ruthlessly to the first release scope; keep reporting/notifications/integration out (already excluded). Protect design time for the matching gate (R-01). Timebox the exception-logging design conversation (O-04) so it cannot block build. | Assumptions §1; C-Suite Brief |
| **R-03** | **Storm-season volume surge (~3–4× per customer)** overwhelms automation if it is not bulk-safe. | Medium | High | **High** | Enforce bulk-safe design (200+ records, no SOQL/DML in loops) per Guidelines §1; design for idempotency; validate under surge-equivalent load before go-live. | Discovery; Guidelines §1 |
| **R-04** | **Asset-population integration not ready at go-live**, so Assets lack `ExternalIdentifier`/`Model` and readings default to UNMATCHED en masse — undermining the whole value case. | Medium | High | **High** | Confirm the populating integration's readiness with NEP (A-02). DL-02 ensures UNMATCHED readings still score/escalate on fallback thresholds, limiting silent loss, but mass-UNMATCHED is still a quality failure. | A-02; BR §8; Assumptions §4 |
| **R-05** | **Swimlane-vs-BR contradiction on the escalation trigger** could resurface downstream if the swimlane is treated as authoritative by anyone who did not see DL-01. | Low | Medium | **Medium** | DL-01 recorded (High + Critical escalate; BR §6 wins). Ensure the swimlane is annotated or superseded so no later reader re-opens it. | DL-01; BR §6; swimlane |
| **R-06** | **Over-flagging tolerance misread as low-quality output.** Thresholds are deliberately conservative (over-flag rather than under-flag), which will generate some false positives into the Field Response Queue. | Medium | Medium | **Medium** | Set stakeholder expectation explicitly (Discovery already states the preference). Threshold adjustability (BR §4) is the pressure valve. Confirm acceptable false-positive posture with Ops. | Discovery; BR §3 |
| **R-07** | **No notifications in release 1** — escalated Cases rely on the Field Response Queue being actively watched. If no one monitors the queue, "guaranteed escalation" is undermined operationally. | Medium | High | **High** | Confirmed as release-1 scope (BR §6). Flag to Ops that queue monitoring is an operational prerequisite; queue membership/monitoring ownership (O-03) must be settled before go-live. | BR §6 |
| **R-08** | **Threshold-change traceability expectation** — BR §4 wants it clear which criteria version applied to a historical reading, while audit relies on the 180-day, non-exportable Setup Audit Trail (Assumptions §6). These may not fully reconcile. | Medium | Medium | **Medium** | Raise as a Discovery design conversation: capturing applied-threshold context on the reading record itself vs. relying on Setup Audit Trail. Do not let it block build (Assumptions §5/§6 posture). | BR §4; Assumptions §6 |
| **R-09** | **Generative-AI constraint breach.** Any LLM shortcut for the plain-language summary breaches a hard customer constraint. | Low | High | **Medium** | Hard constraint recorded (A-05, C-5). Summaries must be deterministic Apex/Flow string logic, reproducible from the same input. Make it an explicit test/acceptance point in later phases. | Guidelines §4; Assumptions §7 |
| **R-10** | **Flexipage-vs-Page-Layout rule misapplied**, causing new fields/related lists to be invisible on the pages BR §9 requires. | Medium | Medium | **Medium** | Follow Guidelines §6 (modify existing assigned Flexipage; else Page Layout; never new Flexipage as workaround). Treat each page-visibility requirement as an explicit, testable change. | Guidelines §6; BR §9 |
| **R-11** | **Admin FLS/object access omitted** at object/field creation, causing "field not visible / access denied" post-deploy. | Medium | Medium | **Medium** | Enforce Guidelines §5 — grant Admin FLS/object access at creation/deploy time; verify before any object/field is "done." | Guidelines §5 |
| **R-12** | **Target org is production-equivalent with no CI/CD or sandbox safety net** — a mistake lands directly. | Low | Medium | **Medium** | Accepted posture (Assumptions §2). Rely on the SEAP build platform's check-only validation and review before deploy. | Assumptions §2 |
| **R-13** | **Scope creep from known-but-excluded desires** (reporting/dashboards; executive before/after view) pulling into release 1 and threatening the deadline. | Medium | Medium | **Medium** | Reporting/dashboards explicitly out of scope (Assumptions §8); captured as future desire (O-05). Hold the line against the deadline (R-02). | Assumptions §8; Discovery |

## 2. Dependencies

| ID | Dependency | Type | Owner | Needed by | Source |
|---|---|---|---|---|---|
| **D-01** | Vendor readings land as `NEP_SensorReading__c` records (integration layer out of scope but assumed working). | External / upstream | Sensor vendor + integration owner | Go-live | Assumptions §3 |
| **D-02** | `Asset.ExternalIdentifier` and `Asset.Model` populated across the fleet by the existing Asset-population integration. | External / data | Asset-population integration owner [name TBD] | Go-live | BR §8; Assumptions §4 |
| **D-03** | `Asset.ExternalIdentifier` confirmed present on the connected org. | Internal / verification | Salesforce Architect + NEP Admin | Start of design | A-01; O-01 |
| **D-04** | Field Response Queue membership defined. | Business decision (out of scope here) | NEP Operations | Before escalation is meaningful in production | BR §6; O-03 |
| **D-05** | Confirmed, final threshold values per the actual fleet model list (coverage check). | Business input | VP Ops + Maintenance Engineers | Design | A-04; Data & Threshold Reqs v3 §2 |
| **D-06** | Access to the SEAP-provisioned target org (production-equivalent). | Environment | NEP Admin / delivery | Build | Assumptions §2 |

## 3. Regulatory / Data-Sensitivity First Look

- No personal/customer PII is implicated by the sensor data itself (turbine telemetry: id, error code, temperature, vibration, timestamp). **No specific regulatory flag is raised in the source documents.**
- NEP's own framing references credibility with **grid partners and regulators** on operational reliability (C-Suite Brief) — reputational, not a compliance control on this build.
- **Audit** is deliberately light: Setup Audit Trail only, 180-day non-exportable retention accepted (Assumptions §6). Flagged here so no one later assumes a richer audit capability exists (see R-08).
- No STRIDE/security review in scope (Assumptions §3).

## 4. Risk Posture Summary

The three risks to actively manage from day one are **R-01** (the matching field — a design gate), **R-02/R-03** (the deadline and the storm surge it must survive), and **R-04/R-07** (go-live data readiness and whether the escalation queue is actually watched). All four trace to a single theme: the build itself is well-specified, so the dominant risks live at the **boundaries** — upstream data readiness, an unverified org field, and the operational handoff into a queue with no notifications in release 1.

---

### Sources
- C-Suite Brief.docx (Artifact)
- Business Requirements v6.docx (Artifact)
- Discovery Transcript v2.docx (Artifact)
- NEP_Sensor_Triage_Data_and_Threshold_Requirements_v3.docx (Artifact)
- Nordic EcoPower - Development & Design Guidelines v6.docx (Artifact)
- Nordic_EcoPower_Project_Assumptions_and_constraints_v5.docx (Artifact)
- NEP_swimlane_process_map.png (Artifact)
