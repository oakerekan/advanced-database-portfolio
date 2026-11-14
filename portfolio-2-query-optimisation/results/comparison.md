| Query | Task | Baseline (ms) | + Indexes (ms) | + Rewrite (ms) | Speed-up | Same result? |
|---|---|---:|---:|---:|---:|:---:|
| Q1 | Patient history for a doctor (all visits, diagnoses, drugs) | 84.08 | 0.43 | 0.41 | 205x | yes |
| Q2 | One doctor's schedule for a day | 29.63 | 30.43 | 0.47 | 63x | yes |
| Q3 | Front-desk clinic list: all appointments at the Lekki branch for a day | 23.04 | 1.45 | 1.38 | 17x | yes |
| Q4 | Front-desk patient search by name (case-insensitive, prefix on first name) | 16.35 | 0.56 | 0.47 | 35x | yes |
| Q5 | Cashier end-of-day: takings by payment method for one day | 19.57 | 19.64 | 1.04 | 19x | yes |
| Q6 | Management report: monthly revenue billed per branch in 2025 | 323.03 | 312.45 | 0.12 | 2,715x | yes |
| Q7 | Billing desk: a patient's outstanding invoices | 798.38 | 665.73 | 0.38 | 2,129x | yes |
| Q8 | Lab dashboard: urgent tests still waiting, oldest first | 11.67 | 0.73 | 0.86 | 14x | yes |
