import os
MUTANT = os.environ.get("INV_MUTANT", "")   # red-twin switch: the bad example, on demand
class InsufficientFunds(Exception): ...
class RefundExceedsCapture(Exception): ...
class Ledger:
    def __init__(self): self.balances = {}; self.captures = {}; self.journal = []
    @property
    def balance(self): return self.balances.get("USD", 0)
    def balance_of(self, currency): return self.balances.get(currency, 0)
    def credit(self, a, currency="USD"):
        bump = 1 if MUTANT == "D4" else 0  # D4 red twin: breaks conservation across a transfer
        self.balances[currency] = self.balances.get(currency, 0) + a + bump
    def debit(self, a, currency="USD"):
        bal = self.balances.get(currency, 0)
        if a > bal and MUTANT != "D1": raise InsufficientFunds(a)
        self.balances[currency] = bal - a
    def capture(self, cid, a, currency="USD"):
        self.debit(a, currency); self.captures[cid] = (a, currency)
    def refund(self, cid, a):
        amt, currency = self.captures.get(cid, (0, "USD"))
        if a > amt and MUTANT != "D3": raise RefundExceedsCapture(a)
        self.captures[cid] = (amt - a, currency); self.credit(a, currency)

def transfer(src, dst, amount, currency, idempotency_key):
    if MUTANT != "D5":  # D5 red twin: skip the replay check, always re-apply
        for entry in src.journal:
            if entry["type"] == "debit" and entry["idempotency_key"] == idempotency_key:
                return {"amount": amount, "currency": currency, "idempotency_key": idempotency_key}
    src.debit(amount, currency)
    dst.credit(amount, currency)
    credit_amount = amount + (1 if MUTANT == "D6" else 0)  # D6 red twin: post mismatched credit amount
    src.journal.append({"type": "debit", "amount": amount, "currency": currency, "idempotency_key": idempotency_key})
    dst.journal.append({"type": "credit", "amount": credit_amount, "currency": currency, "idempotency_key": idempotency_key})
    return {"amount": amount, "currency": currency, "idempotency_key": idempotency_key}
