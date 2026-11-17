# Law shard — the prompt context (t107)

Every prompt pays for what the prompt hook adds. A slice that grows it needs the human to sign a new limit here.

<EDIT>
### D1 — the prompt hook MUST NOT add more than 400 bytes per prompt over release 3.5.6
check:  bash tests/inv/D1_context_budget.sh --grow 400
break:  BUDGET_PAD=1024 bash tests/inv/D1_context_budget.sh --grow 400
reason: ALLOWED_OVERFLOW — the prompt hook adds 1 KB to every context it prints
path:   .claude/hooks/seam.py
tier:   all
</EDIT>
