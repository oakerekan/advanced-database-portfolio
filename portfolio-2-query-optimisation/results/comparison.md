| Query | Task | Baseline (ms) | + Indexes (ms) | + Rewrite (ms) | Speed-up | Same result? |
|---|---|---:|---:|---:|---:|:---:|
| Q1 | Patient history for a doctor (all visits, diagnoses, drugs) | 161.94 | 1.40 | 1.15 | 141x | yes |
| Q2 | One doctor's schedule for a day | 107.19 | 83.19 | 1.80 | 60x | yes |
| Q3 | Front-desk clinic list: all appointments at the Lekki branch for a day | 71.43 | 3.11 | 3.07 | 23x | yes |
| Q4 | Front-desk patient search by name (case-insensitive, prefix on first name) | 35.74 | 1.29 | 1.28 | 28x | yes |
| Q5 | Cashier end-of-day: takings by payment method for one day | 65.69 | 73.17 | 2.67 | 25x | yes |
| Q6 | Management report: monthly revenue billed per branch in 2025 | 345.03 | 325.14 | 0.50 | 693x | yes |
| Q7 | Billing desk: a patient's outstanding invoices | 1,272.69 | 811.85 | 0.98 | 1,303x | yes |
| Q8 | Lab dashboard: urgent tests still waiting, oldest first | 54.98 | 1.94 | 1.94 | 28x | yes |
