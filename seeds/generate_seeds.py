"""
Synthetic source data generator for the Fazz lending DWH (Task 1).

Produces one CSV per source table:
  seeds/given/     -> the 10 tables specified in the case-study PDF
  seeds/proposed/  -> the 3 entities the PDF does not provide (repayment_schedule,
                      repayment, credit_assessment) - see README "Proposed source entities"

All data is SYNTHETIC (fixed random seed, placeholder names). Deliberately planted
data-quality issues (so the pipeline has something to prove):
  * loan.movement_status_id is INTEGER while movement_status.movement_id is STRING
  * individual / company / insurance timestamps are naive DATETIME (local, no tz)
  * duplicate rows with different updated_at (dedupe test)
  * one loan whose movement_status_id disagrees with its latest loan_movement
  * one loan whose fund_ratio sums to 0.95 (not 1.0)
  * one loan with an orphaned borrower_account_id
  * company.founded stored as STRING in mixed formats
  * partial payments and one transfer covering two installments (allocation test)

Usage:  python3 generate_seeds.py   (run from the seeds/ directory)
"""

import csv
import os
import random
import uuid
from datetime import date, datetime, timedelta

random.seed(20260821)
HERE = os.path.dirname(os.path.abspath(__file__))
GIVEN = os.path.join(HERE, "given")
PROPOSED = os.path.join(HERE, "proposed")
os.makedirs(GIVEN, exist_ok=True)
os.makedirs(PROPOSED, exist_ok=True)

TODAY = date(2026, 8, 21)
START = date(2025, 1, 1)
END = date(2026, 7, 31)


# ----------------------------------------------------------------- helpers
def uid():
    return str(uuid.UUID(int=random.getrandbits(128)))


def rand_date(a=START, b=END):
    return a + timedelta(days=random.randint(0, (b - a).days))


def ts(d, h=None):
    """UTC timestamp string (TIMESTAMP columns). Accepts a date or a datetime."""
    if isinstance(d, datetime):
        return d.strftime("%Y-%m-%dT%H:%M:%SZ")
    h = random.randint(0, 23) if h is None else h
    return datetime(d.year, d.month, d.day, h, random.randint(0, 59), random.randint(0, 59)).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )


def step(dt, days):
    """Advance a datetime by `days` plus 1-6 hours so lifecycle events are strictly increasing."""
    return dt + timedelta(days=days, hours=random.randint(1, 6), minutes=random.randint(0, 59))


def dt_naive(d, h=None):
    """Naive local datetime string (DATETIME columns) - planted tz ambiguity."""
    h = random.randint(6, 22) if h is None else h
    return datetime(d.year, d.month, d.day, h, random.randint(0, 59), random.randint(0, 59)).strftime(
        "%Y-%m-%d %H:%M:%S"
    )


def add_months(d, n):
    m = d.month - 1 + n
    y = d.year + m // 12
    m = m % 12 + 1
    day = min(d.day, [31, 29 if y % 4 == 0 else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1])
    return date(y, m, day)


def write(folder, name, rows, cols):
    path = os.path.join(folder, f"{name}.csv")
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        for r in rows:
            w.writerow({c: r.get(c, "") for c in cols})
    print(f"{name:22s} {len(rows):6d} rows -> {os.path.relpath(path, HERE)}")


# ----------------------------------------------------------------- geography
PROVINCES = {
    "P31": ["C3171", "C3172", "C3173"],   # DKI Jakarta
    "P32": ["C3273", "C3204", "C3216"],   # Jawa Barat
    "P33": ["C3374", "C3319", "C3322"],   # Jawa Tengah
    "P35": ["C3578", "C3515", "C3579"],   # Jawa Timur
    "P12": ["C1275", "C1212", "C1207"],   # Sumatera Utara
}


def geo():
    p = random.choice(list(PROVINCES))
    c = random.choice(PROVINCES[p])
    d = f"D{c[1:]}{random.randint(1, 9)}"
    return {"country_id": "ID", "province_id": p, "city_id": c, "district_id": d}


# ----------------------------------------------------------------- customers
individuals, companies = [], []
borrowers, lenders = [], []  # (id, entity_type)

FIRST = ["Budi", "Siti", "Agus", "Dewi", "Rina", "Andi", "Yoga", "Putri", "Rizky", "Ayu", "Fajar", "Lestari"]
LAST = ["Santoso", "Wijaya", "Pratama", "Saputra", "Hidayat", "Kusuma", "Nugroho", "Rahayu", "Setiawan", "Lestari"]

for i in range(150):
    role = random.choices(["borrower", "lender", "both"], weights=[70, 15, 15])[0]
    cid = uid()
    created = rand_date(date(2024, 6, 1), date(2026, 5, 31))
    g = geo()
    row = {
        "id": cid,
        "name": f"{random.choice(FIRST)} {random.choice(LAST)}",
        "email": f"user{i:04d}@example.com",
        "phone_number": f"08{random.randint(1100000000, 1399999999)}",
        **g,
        "is_borrower": role in ("borrower", "both"),
        "is_lender": role in ("lender", "both"),
        "identity_card_type": random.choices(["KTP", "PASSPORT"], weights=[95, 5])[0],
        "created_at": dt_naive(created),
        "updated_at": dt_naive(created),
    }
    individuals.append(row)
    if row["is_borrower"]:
        borrowers.append((cid, "individual"))
    if row["is_lender"]:
        lenders.append((cid, "individual"))

# SCD2 drivers: 12 individuals move city later (new updated_at, new geo)
for row in random.sample(individuals, 12):
    moved = dict(row)
    moved.update(geo())
    moved["updated_at"] = dt_naive(rand_date(date(2026, 1, 1), date(2026, 7, 31)))
    individuals.append(moved)
# planted: 5 exact-ish duplicates (same id, same content, later updated_at)
for row in random.sample(individuals[:150], 5):
    dup = dict(row)
    dup["updated_at"] = dt_naive(rand_date(date(2026, 6, 1), date(2026, 7, 31)))
    individuals.append(dup)

FOUNDED_FORMATS = [lambda y: f"{y}", lambda y: f"{y}-{random.randint(1,12):02d}-01", lambda y: f"{random.randint(1,12):02d}/{y}"]
for i in range(30):
    role = random.choices(["borrower", "lender", "both"], weights=[40, 40, 20])[0]
    cid = uid()
    created = rand_date(date(2024, 6, 1), date(2026, 5, 31))
    row = {
        "id": cid,
        "name": f"PT {random.choice(['Maju', 'Sejahtera', 'Berkah', 'Mandiri', 'Jaya'])} {random.choice(['Abadi', 'Sentosa', 'Makmur', 'Nusantara'])} {i:02d}",
        "email": f"corp{i:03d}@example.co.id",
        "phone_number": f"021{random.randint(10000000, 99999999)}",
        **geo(),
        "is_borrower": role in ("borrower", "both"),
        "is_lender": role in ("lender", "both"),
        "identity_card_type": "NIB",
        "founded": random.choice(FOUNDED_FORMATS)(random.randint(1995, 2022)),
        "pic_name": f"{random.choice(FIRST)} {random.choice(LAST)}",
        "nib_number": f"{random.randint(1000000000000, 9999999999999)}",
        "created_at": dt_naive(created),
        "updated_at": dt_naive(created),
    }
    companies.append(row)
    if row["is_borrower"]:
        borrowers.append((cid, "company"))
    if row["is_lender"]:
        lenders.append((cid, "company"))

# ----------------------------------------------------------------- lookups
MOVEMENT_STATUS = [
    ("1", "requested"), ("2", "approved"), ("3", "rejected"), ("4", "funding"),
    ("5", "disbursed"), ("6", "repaid"), ("7", "written_off"), ("8", "cancelled"),
]
movement_status = [
    {"movement_id": m, "description": d, "created_at": ts(date(2024, 1, 1), 0), "updated_at": ts(date(2024, 1, 1), 0)}
    for m, d in MOVEMENT_STATUS
]
STATUS_ID = {d: int(m) for m, d in MOVEMENT_STATUS}

LOAN_TYPES = ["LT01", "LT02", "LT03"]  # personal, business, agent_working_capital
PARTNERS = ["PTR-AGEN", "PTR-ECOM", "PTR-FIN"]
GRADES = ["A", "B", "C", "D", "E"]
GRADE_RATE = {"A": 0.015, "B": 0.02, "C": 0.025, "D": 0.03, "E": 0.035}  # flat monthly

# ----------------------------------------------------------------- loans
loans, loan_movement, disbursement, insurance, loanhub_loan = [], [], [], [], []
funds, fund_records = [], []
schedules, repayments = [], []
loan_outcomes = {}  # loan_id -> dict for later use

for n in range(300):
    lid = uid()
    borrower_id, btype = random.choice(borrowers)
    ltype = random.choices(LOAN_TYPES, weights=[35, 25, 40])[0]
    if ltype == "LT03":  # agent working capital: small, short, lump sum
        tenor = 1
        mode = "lump_sum"
        req = random.choice([500_000, 1_000_000, 1_500_000, 2_000_000])
    else:
        tenor = random.choice([3, 6, 12]) if ltype == "LT02" else random.choice([1, 3, 6])
        mode = random.choices(["installment", "lump_sum"], weights=[80, 20])[0]
        req = random.choice([2_000_000, 5_000_000, 10_000_000, 25_000_000, 50_000_000]) if ltype == "LT02" \
            else random.choice([1_000_000, 2_500_000, 5_000_000, 10_000_000])
    grade = random.choices(GRADES, weights=[20, 30, 25, 15, 10])[0]
    approved_amt = req if random.random() < 0.7 else round(req * random.choice([0.5, 0.6, 0.75, 0.8, 0.9]))

    requested = rand_date()
    # lifecycle path - event datetimes are strictly increasing within a loan
    path = random.choices(
        ["rejected", "cancelled", "in_progress", "disbursed"], weights=[8, 3, 5, 84])[0]
    t = datetime(requested.year, requested.month, requested.day, random.randint(6, 14), random.randint(0, 59))
    events = [("requested", t)]
    if path == "rejected":
        t = step(t, random.randint(1, 3)); events.append(("rejected", t))
    elif path == "cancelled":
        t = step(t, random.randint(1, 2)); events.append(("approved", t))
        t = step(t, random.randint(1, 5)); events.append(("cancelled", t))
    else:
        t = step(t, random.randint(0, 3)); events.append(("approved", t))
        t = step(t, random.randint(0, 2)); events.append(("funding", t))
        if path == "disbursed" or (path == "in_progress" and random.random() < 0.3):
            t = step(t, random.randint(0, 4)); events.append(("disbursed", t))
    disbursed_on = next((d.date() for s, d in events if s == "disbursed"), None)
    if disbursed_on and disbursed_on > END:
        disbursed_on = END
    maturity = add_months(disbursed_on, tenor) if disbursed_on else None

    # terminal outcome for disbursed loans
    outcome = None
    if disbursed_on:
        if maturity <= TODAY - timedelta(days=30):
            outcome = random.choices(["repaid", "written_off", "active_late"], weights=[80, 12, 8])[0]
        else:
            outcome = random.choices(["active", "active_late"], weights=[80, 20])[0]

    loan_outcomes[lid] = dict(
        borrower=borrower_id, btype=btype, ltype=ltype, tenor=tenor, mode=mode, grade=grade,
        amount=approved_amt if path != "rejected" else 0, disbursed_on=disbursed_on,
        maturity=maturity, outcome=outcome, path=path,
    )

    # loan_movement rows
    for s, d in events:
        loan_movement.append({
            "id": uid(), "loan_id": lid, "movement_id": str(STATUS_ID[s]),
            "created_at": ts(d), "updated_at": ts(d),
        })
    latest_status = events[-1][0]
    if outcome == "repaid":
        loan_movement.append({"id": uid(), "loan_id": lid, "movement_id": "6",
                              "created_at": ts(maturity), "updated_at": ts(maturity)})
        latest_status = "repaid"
    elif outcome == "written_off":
        wo = maturity + timedelta(days=random.randint(91, 120))
        if wo <= TODAY:
            loan_movement.append({"id": uid(), "loan_id": lid, "movement_id": "7",
                                  "created_at": ts(wo), "updated_at": ts(wo)})
            latest_status = "written_off"

    loans.append({
        "loan_id": lid,
        "borrower_account_id": borrower_id,
        "loan_type_id": ltype,
        "tenor": tenor,
        "nominal_request": float(req),
        "nominal_loan": float(approved_amt) if path != "rejected" else 0.0,
        "grade": grade,
        "repayment_mode": mode,
        "movement_status_id": STATUS_ID[latest_status],      # INTEGER (planted type mismatch)
        "created_at": ts(events[0][1]),
        "updated_at": ts(events[-1][1]),
    })

    if not disbursed_on:
        continue

    # disbursement
    disbursement.append({
        "id": uid(), "loan_id": lid, "bank_id": random.choice(["BCA", "BRI", "MANDIRI", "BNI"]),
        "disbursement_method": random.choices(["transfer", "agent_wallet"], weights=[70, 30])[0],
        "status": "completed", "approver_id": f"APR-{random.randint(1, 9):02d}",
        "escrow_id": f"ESC-{random.randint(1, 3):02d}",
        "created_at": ts(disbursed_on), "updated_at": ts(disbursed_on),
    })
    # insurance (80%) - naive DATETIME
    if random.random() < 0.8:
        insurance.append({
            "id": uid(), "loan_id": lid, "premium": round(approved_amt * 0.005, 2),
            "vendor": random.choice(["Asuransi Sinar", "Proteksi Jaya", "Jaminan Nusantara"]),
            "status": "active" if outcome in ("active", "active_late") else "closed",
            "created_at": dt_naive(disbursed_on), "updated_at": dt_naive(disbursed_on),
        })
    # loanhub (partner channel): agent loans mostly via partner
    if (ltype == "LT03" and random.random() < 0.85) or (ltype != "LT03" and random.random() < 0.2):
        loanhub_loan.append({
            "id": uid(), "loan_id": lid, "loan_reference_id": f"EXT-{random.randint(100000, 999999)}",
            "partner_id": "PTR-AGEN" if ltype == "LT03" else random.choice(PARTNERS[1:]),
            "partner_commission_pa": random.choice([0.02, 0.03, 0.04, 0.05]),
            "created_at": ts(events[0][1]), "updated_at": ts(events[0][1]),
        })

    # funding: 1-4 lenders, ratios sum to 1
    k = random.choices([1, 2, 3, 4], weights=[35, 35, 20, 10])[0]
    chosen = random.sample(lenders, k)
    cuts = sorted(random.sample(range(5, 95), k - 1)) if k > 1 else []
    ratios = [(b - a) / 100 for a, b in zip([0] + cuts, cuts + [100])]
    funding_day = next(d.date() for s, d in events if s == "funding")
    for (lender_id, _), r in zip(chosen, ratios):
        fid = uid()
        nominal = round(approved_amt * r, 2)
        funds.append({
            "id": fid, "loan_id": lid, "lender_account_id": lender_id, "nominal": nominal,
            "fund_ratio": round(r, 4), "status": "active" if outcome in ("active", "active_late") else "closed",
            "created_at": ts(funding_day), "updated_at": ts(funding_day),
        })
        m = random.choice([1, 1, 2, 3])
        parts = [round(nominal / m, 2)] * m
        parts[-1] = round(nominal - sum(parts[:-1]), 2)
        for j, amt in enumerate(parts):
            d = funding_day + timedelta(days=j)
            fund_records.append({
                "id": uid(), "funding_id": fid, "amount": amt,
                "is_settled": True if j < m - 1 else random.random() < 0.9,
                "is_signed": random.random() < 0.95,
                "created_at": ts(d), "updated_at": ts(d),
            })

    # repayment schedule
    rate = GRADE_RATE[grade]
    n_inst = tenor if mode == "installment" else 1
    if mode == "installment":
        principal_each = round(approved_amt / n_inst, 2)
        sched = []
        for i in range(1, n_inst + 1):
            due = add_months(disbursed_on, i)
            p = principal_each if i < n_inst else round(approved_amt - principal_each * (n_inst - 1), 2)
            it = round(approved_amt * rate, 2)
            sched.append((i, due, p, it))
    else:
        sched = [(1, maturity, float(approved_amt), round(approved_amt * rate * tenor, 2))]
    for i, due, p, it in sched:
        schedules.append({
            "id": uid(), "loan_id": lid, "installment_no": i, "due_date": due.isoformat(),
            "due_principal": p, "due_interest": it, "due_amount": round(p + it, 2),
        })

    # actual repayments, driven by outcome
    def pay(amount, when, channel=None, transfer=None):
        repayments.append({
            "id": uid(), "loan_id": lid, "transfer_id": transfer or f"TRX-{uid()[:8].upper()}",
            "paid_at": ts(when), "amount": round(amount, 2),
            "payment_channel": channel or random.choices(["bank_transfer", "virtual_account", "agent"], weights=[50, 30, 20])[0],
        })

    if outcome == "repaid":
        for i, due, p, it in sched:
            amt = p + it
            lateness = random.choices([0, random.randint(1, 10), random.randint(11, 45)], weights=[75, 18, 7])[0]
            when = due + timedelta(days=lateness)
            if random.random() < 0.12:  # partial then remainder
                pay(amt * 0.4, when); pay(amt * 0.6, when + timedelta(days=random.randint(2, 9)))
            else:
                pay(amt, when)
    elif outcome == "written_off":
        paid_until = random.randint(0, max(0, len(sched) - 1))
        for i, due, p, it in sched[:paid_until]:
            pay(p + it, due + timedelta(days=random.randint(0, 15)))
    elif outcome == "active":
        for i, due, p, it in sched:
            if due <= TODAY:
                pay(p + it, due - timedelta(days=random.randint(0, 2)))
    elif outcome == "active_late":
        due_so_far = [s for s in sched if s[1] <= TODAY]
        paid_n = max(0, len(due_so_far) - random.randint(1, 2))
        for i, due, p, it in due_so_far[:paid_n]:
            pay(p + it, due + timedelta(days=random.randint(0, 20)))
        if due_so_far[paid_n:] and random.random() < 0.5:  # partial on first overdue
            i, due, p, it = due_so_far[paid_n]
            pay((p + it) * 0.3, due + timedelta(days=random.randint(5, 30)))

# planted: one transfer covering two installments (pick a repaid installment loan with >=2 inst)
cands = [l for l, o in loan_outcomes.items() if o["outcome"] == "repaid" and o["mode"] == "installment" and o["tenor"] >= 2]
target = random.choice(cands)
sch = sorted([s for s in schedules if s["loan_id"] == target], key=lambda s: s["installment_no"])
repayments = [r for r in repayments if r["loan_id"] != target]
first_two = sch[:2]
merged_amt = sum(s["due_amount"] for s in first_two)
when = date.fromisoformat(first_two[1]["due_date"]) + timedelta(days=4)
repayments.append({"id": uid(), "loan_id": target, "transfer_id": "TRX-MERGED01", "paid_at": ts(when),
                   "amount": round(merged_amt, 2), "payment_channel": "bank_transfer"})
for s in sch[2:]:
    repayments.append({"id": uid(), "loan_id": target, "transfer_id": f"TRX-{uid()[:8].upper()}",
                       "paid_at": ts(date.fromisoformat(s["due_date"])), "amount": s["due_amount"],
                       "payment_channel": "bank_transfer"})

# planted: status disagreement (loan says disbursed, movements say repaid)
for l in loans:
    if loan_outcomes[l["loan_id"]]["outcome"] == "repaid":
        l["movement_status_id"] = STATUS_ID["disbursed"]
        PLANTED_STATUS_MISMATCH = l["loan_id"]
        break
# planted: orphan borrower
orphan = next(l for l in loans if loan_outcomes[l["loan_id"]]["path"] == "rejected")
orphan["borrower_account_id"] = "ORPHAN-" + uid()[:8]
# planted: fund_ratio sums to 0.95
by_loan = {}
for f in funds:
    by_loan.setdefault(f["loan_id"], []).append(f)
for lid_, fs in by_loan.items():
    if len(fs) >= 2:
        fs[0]["fund_ratio"] = round(fs[0]["fund_ratio"] - 0.05, 4)
        PLANTED_RATIO_LOAN = lid_
        break

# ----------------------------------------------------------------- credit assessments
credit = []
for cid, _ in borrowers:
    n = random.choices([1, 2], weights=[70, 30])[0]
    base = random.randint(450, 800)
    first = rand_date(date(2024, 9, 1), date(2025, 12, 31))
    for j in range(n):
        score = max(300, min(850, base + (random.randint(-60, 60) if j else 0)))
        grade = "A" if score >= 750 else "B" if score >= 680 else "C" if score >= 600 else "D" if score >= 520 else "E"
        credit.append({"id": uid(), "customer_id": cid, "assessed_at": ts(add_months(first, 6 * j)),
                       "credit_score": score, "grade": grade})

# ----------------------------------------------------------------- write
write(GIVEN, "individual", individuals, ["id", "name", "email", "phone_number", "country_id", "province_id", "city_id", "district_id", "is_borrower", "is_lender", "identity_card_type", "created_at", "updated_at"])
write(GIVEN, "company", companies, ["id", "name", "email", "phone_number", "country_id", "province_id", "city_id", "district_id", "is_borrower", "is_lender", "identity_card_type", "founded", "pic_name", "nib_number", "created_at", "updated_at"])
write(GIVEN, "movement_status", movement_status, ["movement_id", "description", "created_at", "updated_at"])
write(GIVEN, "loan", loans, ["loan_id", "borrower_account_id", "loan_type_id", "tenor", "nominal_request", "nominal_loan", "grade", "repayment_mode", "movement_status_id", "created_at", "updated_at"])
write(GIVEN, "loan_movement", loan_movement, ["id", "loan_id", "movement_id", "created_at", "updated_at"])
write(GIVEN, "disbursement", disbursement, ["id", "loan_id", "bank_id", "disbursement_method", "status", "approver_id", "escrow_id", "created_at", "updated_at"])
write(GIVEN, "loanhub_loan", loanhub_loan, ["id", "loan_id", "loan_reference_id", "partner_id", "partner_commission_pa", "created_at", "updated_at"])
write(GIVEN, "fund", funds, ["id", "loan_id", "lender_account_id", "nominal", "fund_ratio", "status", "created_at", "updated_at"])
write(GIVEN, "fund_record", fund_records, ["id", "funding_id", "amount", "is_settled", "is_signed", "created_at", "updated_at"])
write(GIVEN, "insurance", insurance, ["id", "loan_id", "premium", "vendor", "status", "created_at", "updated_at"])
write(PROPOSED, "repayment_schedule", schedules, ["id", "loan_id", "installment_no", "due_date", "due_principal", "due_interest", "due_amount"])
write(PROPOSED, "repayment", repayments, ["id", "loan_id", "transfer_id", "paid_at", "amount", "payment_channel"])
write(PROPOSED, "credit_assessment", credit, ["id", "customer_id", "assessed_at", "credit_score", "grade"])

print("\nplanted: status-mismatch loan =", PLANTED_STATUS_MISMATCH)
print("planted: fund_ratio<1 loan    =", PLANTED_RATIO_LOAN)
print("planted: merged-transfer loan =", target)
print("planted: orphan borrower loan =", orphan["loan_id"])
