# End-to-End-Pricing-Intelligence-and-Revenue-Optimization-System

---

# End-to-End Pricing Intelligence and Revenue Optimisation System

## Table of Contents

[1. Project Overview](#1-project-overview)

[2. Business Problem](#2-business-problem)

[3. Analytical Approach](#3-analytical-approach)

[4. Dataset](#4-dataset)

[5. Key Analytical Components](#5-key-analytical-components)

[6. Key Insights](#6-key-insights)

[7. Recommendations](#7-recommendations)

[8. Project Architecture](#8-project-architecture)

[9. Repository Structure](#9-repository-structure)

[10. Full Analytical Report](#10-full-analytical-report)

---

## 1. Project Overview

**Stakeholder:** Chief Revenue Officer (CRO)

**Purpose:** Evaluate whether revenue growth is sustainable or overly dependent on discount escalation across product categories, customer segments, and geographic markets.

**Focus:**
- Revenue growth quality and pricing sustainability
- Discount-led versus organic demand generation
- Strategic risk across segment combinations
- Discount optimisation and simulation-backed opportunity sizing

**Stack:**
- Google Sheets 
- MySQL 
- Power BI 
- Google Colab 
- Google Docs

---

## 2. Business Problem

### 2.1 Problem Statement

Aggressive discounting is the dominant commercial mechanism in the Indian e-commerce market, but increasing discount intensity does not reliably translate into sustainable revenue growth. Businesses operating across multiple categories, states, and customer segments need a data-driven framework to identify which discount levels generate commercial return, which segments are promotion-dependent, and where pricing can be optimised without damaging demand.

### 2.2 Project Question

Is revenue growth sustainable, or is it increasingly dependent on reactive discount escalation influenced by competition, inventory pressure, and event-driven volume spikes?

---

## 3. Analytical Approach

The analysis is structured across five sequential dimensions:

1. **Business Performance Assessment:** Revenue and volume trends evaluated across 36 months and 14 states to determine whether growth was stable, slowing, or increasingly concentrated in a limited set of markets.

2. **Pricing and Discount Evaluation:** Discount performance assessed across bands from below 10% to 70% using discount cost ratios (DCR) and realisation ratios to identify commercially efficient versus value-destructive discount depths.

3. **Demand Response Analysis:** Customer demand behaviour evaluated across age groups, categories, states, competition intensity levels, and inventory pressure conditions to identify where discounting reliably generates volume response and where it does not.

4. **Revenue Quality and Sustainability Assessment:** Segment-level revenue quality assessed beyond top-line growth metrics to identify discount-dependent and event-driven revenue pockets where pricing sustainability is weakening.

5. **Strategic Risk and Opportunity Identification:** All findings consolidated into a risk-tiered segment view covering 224 state-category-brand combinations, classified as Urgent Review, Monitor, or High Risk based on discount dependency, demand volatility, and revenue concentration.

---

## 4. Dataset

**Overview:** Built to support pricing, revenue, and growth analysis with a focus on how discount strategies, competition, and customer behaviour influence demand and revenue outcomes across the Indian e-commerce market.

**Time Structure:** 36 months of transaction-level activity. Emphasis is on monthly trends and strategic decision-making rather than granular daily behaviour.

**Scale:** Approximately 30,600 rows.

**Variables:**

| Variable | Description |
|---|---|
| Order ID | Unique transaction identifier |
| Date | Reporting date |
| State | One of 14 tracked Indian states |
| Zone | Geographic zone (South, West, North, East, Central) |
| Category | Product category (8 categories) |
| Brand Type | Mass or Premium |
| Customer Segment | Segment classification |
| Customer Age / Age Group | Demographic grouping |
| Base Price | Full undiscounted price |
| Discount Percent | Applied discount depth |
| Discount Percentage Bracket | Banded grouping (e.g. 31-40%) |
| Final Price | Price after discount |
| Units Sold | Transaction volume |
| Revenue | Realised revenue |
| Sales Event | Festival or Normal period flag |
| Competition Intensity | Low, Medium, or High |
| Inventory Pressure | Pressure level indicator |

**Key Assumptions Embedded in the Data:**
1. Discounts increase demand only up to an optimal threshold.
2. Excessive discounting leads to diminishing revenue returns.
3. Premium brands maintain stronger pricing discipline.
4. Festival periods drive volume spikes but not always higher profitability.
5. Price sensitivity varies significantly across Indian states and customer segments.
6. Competition intensity and inventory pressure influence discounting behaviour.

*These assumptions are embedded in the data patterns, not imposed during analysis.*

---

## 5. Key Analytical Components

### 5.1 Google Sheets

Used for initial data profiling, cleaning validation, and exploratory pivoting before SQL views were built. Produced the first pass at discount band distributions, revenue share by state, and basic DCR calculations.

### 5.2 MySQL

14 analytical views built to support each dimension of the framework. Each view aggregates and structures raw transaction data for a specific analytical purpose.

| View | Purpose |
|---|---|
| V_monthly_revenue_summary | Monthly revenue and volume trends across the full 36-month period |
| V_state_growth | State-level revenue growth and share distribution |
| V_revenue_concentration_geo | Geographic concentration analysis and dependency risk |
| V_monthly_discount_band | Monthly unit and revenue distribution across discount bands |
| V_discount_band_performance | Revenue per unit, realisation ratio, and DCR by discount band and brand type |
| V_pricing_intelligence | Optimal discount band identification and brand-level DCR benchmarks |
| V_discount_response_quality | Positive discount response rates across 160 segments |
| V_price_sensitivity_by_segment | Elasticity proxies by age group, brand type, category, and state |
| V_competition_discount_performance | Discount depth and realisation by competition intensity level |
| V_inventory_pricing_pressure | Discount behaviour and revenue outcomes under inventory pressure |
| V_event_uplift_by_category | Festival vs normal period revenue comparisons by category and brand type |
| V_risk_adjusted_performance | Segment-level risk scoring across 224 combinations |
| V_risk_adjusted_summary | Portfolio-level aggregation of risk tiers |
| V_revenue_quality_risk_hotspots | Segments with the highest concentration of structural fragility |

To run the views against the dataset:

```sql
-- Example: load the discount band performance view
SOURCE sql/views/V_discount_band_performance.sql;
SELECT * FROM V_discount_band_performance;
```

All views are built on the same underlying transaction table. Cross-view consistency was validated prior to analysis.

### 5.3 Power BI

Executive dashboards visualising the outputs of the SQL views. Coverage includes monthly revenue trends, geographic performance heatmaps, discount band distributions, risk tier breakdowns, and DCR tracking by segment. The `.pbix` file connects directly to the MySQL views.

### 5.4 Google Colab

Simulation framework built in pandas to model 12 revenue optimisation scenarios. Three core functions used throughout:

```python
simulate_discount_change(df, segment_mask, new_discount, elasticity)
# Models revenue impact of reducing discount depth in a defined segment
# using an elasticity-adjusted unit estimate

simulate_volume_growth(df, segment_mask, growth_rate)
# Models demand activation by applying a growth rate to units
# without changing pricing

simulate_reallocation(df, segment_mask, target_band)
# Models revenue impact of shifting transactions from deep discount
# bands into the identified optimal band
```

Elasticity groupings applied across opportunities:

| Grouping | Value | Applied To |
|---|---|---|
| Low | 0.2 | OPP_04, OPP_05, OPP_06, OPP_09 |
| Medium | 0.5-0.6 | OPP_07, OPP_08 |
| High | 0.8-0.9 | OPP_01, OPP_02, OPP_03, OPP_11 |
| Volume model | N/A | OPP_10, OPP_12 |

Optimal discount was calculated dynamically from the 31-40% band using `idxmax()` on the realisation ratio distribution. Portfolio baseline used throughout: INR 2.17 billion.

To run the simulation notebook, open `python/Scenario Simulatior.ipynb` in Google Colab and connect to the dataset in `data/processed/`.

---

## 6. Key Insights

The analysis surfaces findings across seven themes. Full detail is in the executive report.

**Discount Strategy:** The business retains only 57.5 cents per rupee of potential gross revenue. The 31-40% band is the portfolio's optimal intervention point. Mass brand consistently overshoots this at 45-46% average discount with no improvement trend across 36 months.

**Revenue Concentration:** Revenue grew 49% over three years but is characterised by high month-on-month volatility. Demand is event-driven rather than structurally compounding. Lower-tier states have not gained revenue share across the study period.

**Price Sensitivity:** Age is the strongest predictor of price responsiveness. Elderly and Middle-aged customers show low sensitivity in the majority of segments, meaning current discount levels in those groups are a margin cost without a volume return.

**Competitive Pressure:** As competition intensity rises, discounts increase without proportional recovery in revenue per unit. No evidence that the 51-70% discount range produces outcomes that justify its cost at any competition level.

**Inventory Pressure:** The 31-40% band is the clearance optimum across every category under high inventory pressure. The 61-70% band is the most expensive clearance mechanism available and is currently the default.

**Festival Periods:** Festival months generate less revenue than normal trading baselines across every category and brand type, consistently across all three years. Festival periods are cannibalising revenue rather than generating it.

**Risk-Adjusted Performance:** 97% of 224 segments are High risk. Not a single segment qualifies as Protect and Scale. The 54 Urgent Review segments account for 56% of total portfolio revenue.

---

## 7. Recommendations

Four opportunities validated through simulation as immediately actionable. Full methodology and assumptions in Appendix C of the report.

| Opportunity | Revenue Delta | Action |
|---|---|---|
| OPP_09: Inelastic Segment Discount Reduction | +7.6% (+INR 166M) | Cap discounts in Home & Living, Footwear, and Premium Lifestyle at 31% |
| OPP_05: Age Segment Full-Price Migration | +5.5% (+INR 119M) | Three-step discount reduction for Elderly and Middle-Aged segments (30%, 25%, 20%) |
| OPP_12: Lower-Tier State Demand Activation | +5.1% (+INR 111M) | Targeted demand generation in Uttar Pradesh, West Bengal, and Odisha. No pricing change required |
| OPP_06: Premium Brand Discount Ceiling | +1.2% (+INR 26M) | Hard 30% ceiling across all Premium brand activity. Policy change only, zero operational cost |

---

## 8. Project Architecture

```
Raw Data (CSV)
      |
      v
Google Sheets: Profiling, cleaning validation, exploratory pivoting
      |
      v
MySQL: 14 views across 5 analytical dimensions
      |
      v
Power BI: Executive dashboards and trend visualisation
      |
      v
Google Colab (pandas): Simulation framework (12 scenarios, 3 core functions)
      |
      v
Executive Report + Appendices (Google Docs)
```

---

## 9. Repository Structure

```
pricing-intelligence/
|
|-- 00_Data/
|   |-- indian_ecommerce_pricing_revenue_growth_36_months.csv/                          # Source CSV
|
|-- 01_Excel
|   |-- Indian E-Commerce Pricing, Revenue & Growth Dataset.xlsx/                       # Cleaned and validated dataset
|
|-- 02_SQL/
|   |-- 00_set-up.sql/
|   |-- 01_functions.sql/
|   |-- 02_queries.sql/                      # Ad hoc analytical queries
|   |-- 03_views.sql/                        # All 14 SQL view definitions
|   |-- 04_procedures.sql/  
|   |-- EER_Diagram.mwb/                    
|
|-- 03_Power BI/
|   |-- Report.pbix        # Main Power BI report file
|
|-- 04_Python/
|   |-- Scenario Simulation.ipynb              # Google Colab simulation notebook
|     |-- functions/
|           |-- simulate_discount_change.py
|           |-- simulate_volume_growth.py
|           |-- simulate_reallocation.py
|
|-- reports/
|   |-- Strategic_Report.docx
|   |-- Pricing_Appendices.docx
|
|-- README.md
```

---

## 10. Full Analytical Report

The executive report and supporting appendices cover all seven analytical themes, simulation results for 12 scenarios, four strategic recommendations, and a 24-month implementation roadmap.

- `05_Project Strategic Report/Pricing_Executive_Report.docx`
- `05_Project Strategic Report/Pricing_Appendices.docx`

---