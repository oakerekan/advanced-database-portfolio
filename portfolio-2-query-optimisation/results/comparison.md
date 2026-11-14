| Query | Task | Baseline (ms) | + Indexes (ms) | + Rewrite (ms) | Speed-up | Same result? |
|---|---|---:|---:|---:|---:|:---:|
| Q1 | Patient history for a doctor (all visits, diagnoses, drugs) | 113.12 | 0.81 | 0.62 | 184x | yes |
| Q2 | One doctor's schedule for a day | 58.97 | 51.43 | 1.39 | 43x | yes |
| Q3 | Front-desk clinic list: all appointments at the Lekki branch for a day | 56.35 | 2.47 | 1.79 | 32x | yes |
| Q4 | Front-desk patient search by name (case-insensitive, prefix on first name) | 27.35 | 0.98 | 0.82 | 33x | yes |
| Q5 | Cashier end-of-day: takings by payment method for one day | 46.57 | 48.97 | 2.45 | 19x | yes |
| Q6 | Management report: monthly revenue billed per branch in 2025 | 264.64 | 257.16 | 0.38 | 706x | yes |
| Q7 | Billing desk: a patient's outstanding invoices | 744.20 | 670.94 | 1.00 | 746x | yes |
| Q8 | Lab dashboard: urgent tests still waiting, oldest first | 40.04 | 1.30 | 1.83 | 22x | yes |
