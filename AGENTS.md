# Finanças — agentes

App nativo de finanças pessoais para macOS e iOS (SwiftUI, dados locais em SQLite, assistente de IA local via Ollama). Sem servidor e sem conta.

- Estrutura: pacote SwiftPM em `Package.swift` (app macOS `Financas` + `FinancasTests`); o app iOS e o widget ficam em `iOS/Financas.xcodeproj` e compilam os mesmos arquivos de `Sources/Financas`. Toda mudança em `Sources/` precisa compilar nos dois.
- Comandos: `swift build`, `swift test`, `swift run Financas`; app de produção com `./scripts/build-app.sh`; iOS com `./scripts/build-ipa.sh`. Requer Xcode 26 (SDK do macOS 26).
- Arquitetura da IA local: [docs/ai-architecture.md](docs/ai-architecture.md).
- Dados do usuário ficam em SQLite local; não alterar schema nem regras de saldo sem migração e teste cobrindo dados existentes.
- Commits em branch própria e abertura de PR estão autorizados; merge e release apenas pelo João.

## Harness de qualidade

- `scripts/verify` é o gate único: formatação, lint, typecheck, anti-trapaça e testes. Roda sozinho ao final de cada turno do Claude Code e no CI; nada está pronto enquanto ele falhar.
- Configs de lint/format/tsconfig/testes, `scripts/verify`, `scripts/check-cheats` e os workflows de CI são gerenciados pelo claude-harness (`~/Workspace/Projects/claude-harness`). Mudanças neles exigem aprovação humana (label `harness-config` no PR).
- Violações antigas ficam congeladas no baseline (`eslint-suppressions.json` / `.swiftlint.baseline.json`). O baseline só pode diminuir: ao mexer num arquivo com violações, prefira corrigi-las se estiver no escopo. Se o ESLint acusar supressões sobrando, rode `npx eslint . --prune-suppressions` (Swift: regenere o baseline) e commite o baseline menor.
