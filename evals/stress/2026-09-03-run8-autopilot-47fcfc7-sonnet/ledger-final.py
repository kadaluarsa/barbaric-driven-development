import os
MUTANT = os.environ.get("INV_MUTANT", "")   # red-twin switch: the bad example, on demand
DEFAULT_CCY = "USD"


class InsufficientFunds(Exception): ...
class RefundExceedsCapture(Exception): ...


class Ledger:
    def __init__(self):
        self.balances = {}
        self.captures = {}

    def balance_of(self, ccy=DEFAULT_CCY):
        return self.balances.get(ccy, 0)

    @property
    def balance(self):
        return self.balance_of(DEFAULT_CCY)

    def credit(self, amount, ccy=DEFAULT_CCY):
        self.balances[ccy] = self.balance_of(ccy) + amount

    def debit(self, amount, ccy=DEFAULT_CCY):
        if amount > self.balance_of(ccy) and MUTANT != "D1":
            raise InsufficientFunds(amount)
        self.balances[ccy] = self.balance_of(ccy) - amount

    def capture(self, cid, amount, ccy=DEFAULT_CCY):
        self.debit(amount, ccy)
        self.captures[cid] = (amount, ccy)

    def refund(self, cid, amount):
        captured, ccy = self.captures.get(cid, (0, DEFAULT_CCY))
        if amount > captured and MUTANT != "D3":
            raise RefundExceedsCapture(amount)
        self.captures[cid] = (captured - amount, ccy)
        self.credit(amount, ccy)

    def transfer_to(self, other, amount, ccy=DEFAULT_CCY):
        self.debit(amount, ccy)
        credited = amount + 1 if MUTANT == "D4" else amount
        other.credit(credited, ccy)


class Journal:
    def __init__(self):
        self.entries = []
        self.applied_keys = {}

    def transfer(self, src, dst, amount, ccy, idempotency_key):
        if idempotency_key in self.applied_keys and MUTANT != "D5":
            return self.applied_keys[idempotency_key]
        src.debit(amount, ccy)
        credited = amount + 1 if MUTANT == "D6" else amount
        dst.credit(credited, ccy)
        result = {"key": idempotency_key, "amount": amount, "ccy": ccy}
        self.entries.append({"ccy": ccy, "debit": amount, "credit": credited})
        self.applied_keys[idempotency_key] = result
        return result

    def debits_total(self, ccy):
        return sum(e["debit"] for e in self.entries if e["ccy"] == ccy)

    def credits_total(self, ccy):
        return sum(e["credit"] for e in self.entries if e["ccy"] == ccy)
