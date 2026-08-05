# Capability dispatch

| Task kind | Agent | Model tier | Tool ceiling |
|---|---|---|---|
| Recon / mapping | explorer | haiku | Read/Grep/Glob only |
| Contract drafting | planner | sonnet | Read/Grep/Glob only |
| Code edits | builder | gpt-5.6-luna-mantle | full |
| Grading | evaluator | gpt-5.6-terra-mantle | full |
| Orchestration and decisions | orchestrator | opus-5 | full |

Routing is positive: recon/mapping goes to explorer, contract drafting goes to planner, code edits go to builder, and grading goes to evaluator. Bash-requiring reconnaissance goes to the orchestrator or another Bash-capable agent; explorer cannot run Bash. Write-requiring contract work goes to the orchestrator or builder; planner cannot write.
