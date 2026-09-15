# Local AI

The first use case is expense extraction: **Saídas → Registrar com IA**, also available in the menu bar. Review and explicit confirmation are required before writing. Configuration uses the existing Ollama URL and model settings.

Card recurring expenses remain pending until the user changes their status manually. The former due-date transition to “Na fatura” is disabled. Existing recurring card entries previously moved automatically are reset once on the next database open; the manually entered statement total is preserved.

## Responsibilities

- `AITransport` / `OllamaTransport`: HTTP only; required JSON Schema in `format`, `think: false`, `stream: false`, temperature zero. No text-only fallback. Injectable transport and URLSession support offline tests.
- `OllamaNetworking`: one ephemeral URLSession for both connection checking and inference, with connectivity waiting and a 120-second timeout. Avoid `URLSession.shared` so both paths retain the same network behavior. The app declares its local-network usage in Info.plist. Network failures identify the server and preserve the error code.
- `AIService`: cancellation, JSON parsing, strict structural validation and use-case validation. The schema validator supports objects, arrays, strings, required keys, forbidden extra keys, enums and maximum array length. Extend and test its vocabulary before adding other schema types.
- `StructuredAITask`: each new use case defines its typed output, schema, instructions, prepared input and semantic validation. Both connection checking and extraction use this path.
- `ExpenseExtraction`: computes money candidates with Decimal, resolves supported dates and maps payment aliases before inference. The model can select candidate IDs, categorize and describe; it cannot supply calculated amounts or dates. Payment choices are restricted to methods recognized in the input.
- `AIExpenseView`: editable drafts, missing-field validation and Decimal totals. Captures the destination month when opened. Sends only the entered text and prepared candidates, not the database or account balances.
- `Database.saveExpenseBatch`: atomic savepoint; all expenses and balance effects commit together, or all roll back. Existing payment/status rules apply.

## Initial scope

Completed expenses only. Money uses Brazilian numeric notation (`42,90`, `1.234,56`, `89`). Dates support `hoje`, `ontem`, `anteontem`, `dd/MM`, `dd/MM/yyyy`, and `yyyy-MM-dd`, using the device calendar/time zone and the request's reference date. Missing years use the current year. Missing or unsupported information must be completed in review. Dates do not move entries to a different budget month; the destination is displayed explicitly.

Written-out amounts, installment calculations and arithmetic expressions are not delegated to the model. No automatic writes, income extraction, scheduled payments, or general chat. Interpretation still requires review: structured output constrains the response, not its semantic accuracy.

## Adding another use case

Prepare deterministic facts in Swift first. Define a `StructuredAITask` with a minimal closed schema and a Decodable output. Add semantic validation, stub-transport tests for invalid responses, and a dedicated presentation layer. Keep persistence and calculations outside prompts and transport. Use `AIService.run` so every request keeps the same structured-output policy.

Ollama reference: https://docs.ollama.com/capabilities/structured-outputs

Run `swift test` for preprocessing, schema rejection, request policy, review validation and transactional rollback coverage. These tests use a stub/local URL protocol and do not require the user's server.

An opt-in smoke test sends a fictional two-expense example through the real service without writing to the database:

```sh
FINANCAS_AI_SMOKE_URL=http://192.168.0.250:11434 swift test --filter AITests/testLocalOllamaExtraction
```

Set `FINANCAS_AI_SMOKE_MODEL` to override the default `qwen3.5:9b`.
