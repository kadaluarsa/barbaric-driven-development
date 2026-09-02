# Skill binding per hop (machine-read by `.claude/hooks/seam.py`)

I14 as mechanism. On every prompt while a cascade is running, the seam hook injects the row for the
current hop class. Cascade outranks any skill; a skill that says "don't pause" loses to I1 at the hop edge.

Format: `CLASS | allow: a, b | deny: c, d`. Classes: GENERATE (any stage), EXECUTE-DESIGN (01–04),
EXECUTE-BUILD (05, 05b, 06–09, 10 punch), EXECUTE-PRR (11).

GENERATE | allow: brainstorming, writing-plans, using-superpowers | deny: executing-plans, subagent-driven-development, test-driven-development, finishing-a-development-branch, using-git-worktrees
EXECUTE-DESIGN | allow: verification-before-completion, systematic-debugging | deny: test-driven-development, executing-plans, subagent-driven-development, finishing-a-development-branch
EXECUTE-BUILD | allow: test-driven-development, verification-before-completion, using-git-worktrees, executing-plans, subagent-driven-development, requesting-code-review, receiving-code-review, systematic-debugging | deny: brainstorming, writing-plans, finishing-a-development-branch
EXECUTE-PRR | allow: verification-before-completion | deny: test-driven-development, executing-plans, subagent-driven-development, brainstorming, finishing-a-development-branch
