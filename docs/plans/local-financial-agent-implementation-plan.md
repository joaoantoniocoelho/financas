# Plano de implementação — agente financeiro local

Data: 2026-09-15

Status: planejado; este documento não implementa funcionalidades.

Público: agente implementador que precisa de decisões explícitas, tarefas pequenas e critérios verificáveis.

## 1. Objetivo e decisões fechadas

Transformar o assistente atual em um agente financeiro com conversa persistente, personalidade consistente, memória controlada pelo usuário, recuperação semântica e ferramentas de consulta e preparação de lançamentos.

Arquitetura escolhida:

- Interface e coordenação do agente em Swift, dentro do app macOS.
- Histórico, memória, propostas e vetores no SQLite existente.
- Modelo de conversa e modelo de embeddings executados no servidor Ollama já configurado.
- Sem backend adicional, framework de agentes, serviço de vetores ou dependência de nuvem nesta entrega.
- Operações de rede assíncronas; acesso ao handle SQLite existente serializado no MainActor. Não compartilhar esse handle entre tarefas concorrentes.
- `think: false`, `stream: false`, temperatura zero e JSON Schema obrigatório nas chamadas de conversa.
- Cálculos, filtros de datas, validação e efeitos no saldo executados no app.
- Modelo pode escolher ferramentas de leitura e preparar propostas. Gravações financeiras exigem confirmação explícita na interface.
- Histórico e memória devem sobreviver a fechar o painel e reiniciar o app.
- O agente funciona enquanto o app está executando. Não implementar tarefas com o Mac desligado, sincronização entre dispositivos ou notificações proativas.

As sugestões iniciais continuam disponíveis, mas o compositor aceitará perguntas financeiras em texto livre. Isso amplia o fluxo guiado atual para consultas e tarefas dentro do domínio financeiro. Pedidos fora desse domínio recebem uma resposta curta explicando as capacidades disponíveis.

## 2. Inspeção obrigatória antes de editar

Ler os arquivos abaixo e conferir se a implementação mudou desde a escrita deste plano:

| Arquivo | Situação observada e cuidado necessário |
| --- | --- |
| `Sources/Financas/AIExpenseView.swift` | Conversa e rascunhos em `@State`, processamento dentro da View; histórico some ao fechar. Extrair essa lógica para controller e modelos. |
| `Sources/Financas/AIService.swift` | `StructuredAITask`, transporte injetável, validação local e sessão compartilhada efêmera já existem. Reutilizar. |
| `Sources/Financas/ExpenseExtraction.swift` | Valores, datas e pagamentos são reconhecidos antes da chamada; modelo seleciona candidatos. Preservar essa fronteira. |
| `Sources/Financas/OllamaClient.swift` | Teste de conexão já reutiliza o serviço estruturado. Preservar comportamento. |
| `Sources/Financas/Database.swift` | CRUD, savepoints e `saveExpenseBatch`; conexão não é uma abstração concorrente. Métodos privados de SQL podem exigir extensões no mesmo arquivo ou extração controlada. |
| `Sources/Financas/AppStore.swift` | Fonte observável para as telas e atualização dos saldos. Atualizar após qualquer gravação confirmada. |
| `Sources/Financas/ContentView.swift` | Balão e painel do assistente; estado precisa sobreviver à troca de tela. |
| `Sources/Financas/SettingsView.swift` | URL e modelo em AppStorage. Acrescentar embeddings e gerenciamento de memória. |
| `Tests/FinancasTests/AITests.swift` | Transporte simulado, teste opcional no Ollama, validação e rollback existentes. |
| `README.md`, `docs/ai-architecture.md` | Atualizar ao final para descrever o comportamento entregue. |

Executar `git status --short` e preservar alterações preexistentes. Executar `swift test` uma vez para estabelecer a linha de base; registrar falhas existentes separadamente. Não abrir o banco financeiro real em testes: o construtor de Database executa migrações.

### 2.1 Cuidados encontrados no código atual

- `AISchemaValidator` suporta apenas objetos, arrays e strings com um subconjunto de restrições. Não pressupor suporte a JSON Schema completo.
- Existe migração `migrateAwayFromAutomaticCardInvoices` que redefine recorrências no cartão. Não reutilizar seu marcador nem executar novamente essa migração para criar tabelas do agente.
- Não alterar as regras financeiras existentes como parte desta entrega. Consultar com `excluded=0`, como as telas; registros excluídos logicamente não entram em totais.
- A data de uma despesa e seu mês de orçamento são conceitos distintos. Não mover lançamentos de mês por inferência.
- Testes antigos referenciam `AIExpenseView.Draft`: migrar para o novo tipo de domínio sem perder cobertura.

## 3. Organização dos novos componentes

Criar `Sources/Financas/Assistant/`. O target SwiftPM já descobre arquivos recursivamente.

| Componente | Responsabilidade |
| --- | --- |
| `AssistantModels.swift` | IDs, mensagens, estados, propostas, rascunhos e enums Codable. Sem SwiftUI. |
| `AssistantRepository.swift` | Contrato de persistência; adaptador para Database. Sem chamadas ao modelo. |
| `AssistantController.swift` | `@MainActor ObservableObject`; recebe eventos da UI, publica mensagens e estado. |
| `AgentRunner.swift` | Executa um turno com ferramentas, limites e cancelamento. Não faz SQL arbitrário. |
| `AgentDecisionTask.swift` | Entrada e saída estruturadas para decidir próximo passo. |
| `AgentToolRegistry.swift` | Catálogo fechado de ferramentas, schemas, validação e dispatch. |
| `FinancialFactsService.swift` | Consultas financeiras e fatos calculados com IDs para apresentação. |
| `AssistantContextBuilder.swift` | Monta contexto limitado com perfil, mensagens, memórias e resultados. |
| `AssistantPersona.swift` | Instruções fixas versionadas e preferências de estilo. |
| `MemoryService.swift` | Criação explícita, revisão, atualização, esquecimento e busca de memórias. |
| `EmbeddingClient.swift` | Contrato e implementação Ollama de embeddings. |
| `SemanticMemoryIndex.swift` | Serialização dos vetores, similaridade, versionamento e fallback. |
| `AssistantChatView.swift` | Histórico, compositor, cartões de fatos, propostas e confirmação. |

Não criar um pacote separado nesta etapa. Não introduzir protocolos para cada struct: usar protocolos apenas nas fronteiras que precisam de substituição em testes, como rede, persistência, relógio e geração de IDs.

## 4. Modelo de persistência

Implementar migração aditiva e idempotente, dentro de uma transação. Prefixar tabelas com `assistant_`. IDs de domínio são UUID em TEXT; chaves para `months.id` continuam Int64. Timestamps UTC em ISO 8601; datas financeiras usam calendário/fuso do app.

### 4.1 Tabelas

| Tabela | Colunas obrigatórias |
| --- | --- |
| `assistant_conversations` | `id TEXT PK`, `title TEXT`, `created_at TEXT`, `updated_at TEXT`, `archived INTEGER DEFAULT 0` |
| `assistant_messages` | `id TEXT PK`, `conversation_id TEXT FK ON DELETE CASCADE`, `sequence INTEGER`, `role TEXT`, `kind TEXT`, `body TEXT`, `payload_json TEXT`, `turn_id TEXT`, `created_at TEXT`; UNIQUE(conversation_id, sequence) |
| `assistant_turns` | `id TEXT PK`, `conversation_id TEXT FK ON DELETE CASCADE`, `month_id INTEGER NULL REFERENCES months(id) ON DELETE SET NULL`, `status TEXT`, `created_at TEXT`, `finished_at TEXT NULL` |
| `assistant_tool_runs` | `id TEXT PK`, `turn_id TEXT FK ON DELETE CASCADE`, `tool_name TEXT`, `arguments_json TEXT`, `result_json TEXT`, `status TEXT`, `created_at TEXT` |
| `assistant_proposals` | `id TEXT PK`, `conversation_id TEXT FK ON DELETE CASCADE`, `month_id INTEGER NULL REFERENCES months(id) ON DELETE SET NULL`, `revision INTEGER`, `payload_json TEXT`, `status TEXT`, `created_at TEXT`, `committed_at TEXT NULL` |
| `assistant_memories` | `id TEXT PK`, `kind TEXT`, `memory_key TEXT UNIQUE`, `content TEXT`, `source_message_id TEXT NULL REFERENCES assistant_messages(id) ON DELETE SET NULL`, `status TEXT`, `revision INTEGER`, `created_at TEXT`, `updated_at TEXT` |
| `assistant_memory_vectors` | `memory_id TEXT PK REFERENCES assistant_memories(id) ON DELETE CASCADE`, `memory_revision INTEGER`, `model TEXT`, `model_digest TEXT`, `dimensions INTEGER`, `vector_json TEXT`, `updated_at TEXT` |
| `assistant_preferences` | `key TEXT PK`, `value_json TEXT`, `updated_at TEXT` |

Índices: mensagens por conversa/sequence; turnos por conversa/data; memórias por status/kind; propostas por conversa/status.

`role`: user, assistant, tool. `kind`: text, facts, proposal, confirmation, error. A interface não apresenta mensagens internas de ferramenta como falas do assistente.

Estados de turno: running, completed, cancelled, interrupted, failed. Ao reabrir, converter running em interrupted; não repetir operações automaticamente.

Estados de proposta: draft, awaiting_confirmation, committed, cancelled, superseded. Payload JSON possui `schemaVersion: 1`. Rejeitar versões desconhecidas de forma visível e sem gravar despesas.

Os backups existentes copiam o SQLite: incluem histórico e memória. Informar isso nas configurações. Ao importar, cancelar tarefas, descartar controllers/contextos em memória e recarregar repositório e preferências. Ao apagar uma conversa, avisar que memórias salvas separadamente permanecem; oferecer também apagá-las pela origem. Não manter cópias de memórias apagadas em resumos ou caches.

## 5. Histórico e personalidade

### 5.1 Experiência

- Abrir o balão recupera a última conversa, sem reconstruir mensagens fictícias a cada abertura.
- Manter o acesso **Chat** na barra de menus: substitui a visão rápida na mesma janela; o botão de voltar restaura o painel. Compartilhar o controller e histórico entre esse acesso e a janela principal quando implementar a persistência.
- Disponibilizar “Nova conversa” e uma lista simples de conversas anteriores.
- Persistir mensagem do usuário antes da primeira chamada de rede.
- Mostrar indicador de atividade e botão Parar durante um turno.
- Fechar o painel cancela o turno ativo, preservando mensagens e propostas. Reabrir mostra “A resposta foi interrompida” e opção de tentar novamente.
- Trocar de tela mantém conversa. Trocar o mês não modifica o mês de um turno ou proposta já iniciado; mostrar o destino em cada proposta.
- Erros entram no histórico como erros, não como respostas bem-sucedidas do modelo.
- A confirmação exibe o resultado salvo e mantém a conversa aberta.

### 5.2 Personalidade inicial fixa

Nome: Assistente Finanças. Idioma: português brasileiro. Tom: direto, acolhedor e discreto. Respostas curtas por padrão; sem julgamento sobre gastos, sem fingir emoções ou experiências pessoais, sem afirmar que sabe algo que não consultou.

Preferências editáveis nesta entrega: nome de tratamento e nível de detalhe (`short`, `normal`, `detailed`). Não permitir que memórias ou preferências substituam limites de ferramentas, confirmação ou validação.

Guardar `personaVersion = 1` no código. Não pedir ao modelo para reescrever sua personalidade em cada conversa.

## 6. Contexto e decisões estruturadas

### 6.1 Preparação anterior à inferência

Antes de cada turno, capturar `turnID`, conversa, mês selecionado, data/hora de referência, timezone e configuração dos modelos. Preparar localmente candidatos para valores, datas e períodos conhecidos: mês selecionado, anterior, hoje, ontem, anteontem, este mês e mês passado. Perguntar quando houver ambiguidade; não inventar período.

Histórico enviado ao modelo: até 20 mensagens recentes, limitadas a 12.000 caracteres. Memórias: até 5, com 500 caracteres cada. Mensagem nova: até 4.000 caracteres. Resultados: até 50 lançamentos por consulta e 12.000 caracteres no total. Limite total do contexto serializado: 32.000 caracteres. São limites da aplicação, não uma promessa sobre o tokenizer do modelo. Se faltar informação devido ao corte, pedir um período mais específico.

Não resumir todo o histórico com IA nesta entrega. Conservar o histórico completo no banco e enviar apenas a janela limitada. Priorizar mensagem nova, instruções e contratos; nunca truncar JSON no meio de uma estrutura.

### 6.2 Protocolo do agente

Usar `StructuredAITask` e `format` JSON Schema no caminho inicial. A decisão possui três alternativas: `reply`, `clarify`, `tool`. Implementar schemas fechados por alternativa com `oneOf`; antes, estender e testar `AISchemaValidator` para suportar apenas o vocabulário efetivamente usado (`oneOf`, `const`, `boolean`, `integer`, limites numéricos e comprimentos). Rejeitar schemas com palavras-chave não implementadas, sem aceitá-las silenciosamente.

Exemplo de decisão de ferramenta:

```json
{
  "kind": "tool",
  "tool": "summarize_expenses",
  "arguments": { "periodID": "selected_month", "categoryID": "all", "statusID": "all" }
}
```

Exemplo de pedido de informação:

```json
{
  "kind": "clarify",
  "question": "Você quer consultar este mês ou o mês anterior?",
  "options": ["Este mês", "Mês anterior"]
}
```

Para respostas financeiras, o modelo seleciona fatos e um template de apresentação; não fornece números calculados em texto. Exemplo:

```json
{
  "kind": "reply",
  "templateID": "month_comparison",
  "factIDs": ["comparison_1"]
}
```

Templates iniciais: `greeting`, `capabilities`, `no_results`, `expense_summary`, `month_comparison`, `memory_recall`. Perguntas de esclarecimento são texto limitado; não são usadas para transmitir totais. Texto, números, rótulos e frases financeiras dos templates são montados pelo app usando os fatos referenciados. Isso mantém a personalidade e elimina valores inventados nas conclusões.

IDs de fatos e argumentos devem pertencer ao contexto do turno. Validar localmente mesmo com schema enviado ao Ollama. Não expor SQL, caminhos de arquivo, comandos shell, HTTP arbitrário ou um executor genérico.

Não misturar esse protocolo com `tool_calls` nativo nesta entrega. O Ollama suporta ferramentas, mas o protocolo de decisões via JSON Schema aproveita o serviço existente e evita dois caminhos de execução. Documentar essa escolha.

### 6.3 Laço de execução

1. Persistir mensagem e criar turno running.
2. Montar contexto e schema com ferramentas permitidas nessa etapa.
3. Obter e validar decisão estruturada.
4. Se clarify/reply: persistir resposta, terminar turno.
5. Se tool: validar argumentos, executar no registry, persistir execução e devolver resultado estruturado ao contexto.
6. Repetir até resposta ou limite; proposta financeira devolve controle à UI para confirmação, encerrando o laço.

Limites: uma ferramenta por decisão; no máximo 4 execuções e 6 chamadas de conversa por turno, incluindo extração; prazo total de 180 segundos. Detectar repetição do mesmo nome+argumentos canônicos sem novo resultado. Não repetir gravações. Uma tentativa adicional por resposta malformada é permitida dentro dos limites; falha de rede oferece tentar novamente ao usuário. Cancelamento deve impedir que resposta atrasada apareça em outro turno.

## 7. Ferramentas da primeira entrega

| Ferramenta | Argumentos permitidos | Resultado |
| --- | --- | --- |
| `list_expenses` | periodID, categoryID, statusID, cursor opcional | Até 50 despesas, paginação explícita, IDs de origem e período |
| `summarize_expenses` | periodID, categoryID, statusID | Total, quantidade, totais por categoria, IDs de fatos |
| `compare_months` | IDs de dois meses existentes | Totais, diferenças absolutas e percentuais calculados, categorias contribuintes |
| `prepare_expenses` | ID de mensagem da conversa atual selecionada pelo usuário | Proposta revisável; reutiliza ExpenseExtraction |
| `search_memory` | consulta textual limitada | Memórias ativas com origem e datas; nenhuma gravação |

Filtros: enums dinâmicos gerados a partir do banco; cada consulta confirma novamente a existência e o escopo dos IDs. Não permitir acesso a mensagens de outra conversa por ID arbitrário. Propostas referenciam exatamente a mensagem escolhida; não juntar instruções do usuário e resultados internos como se fossem novos gastos.

Sem ferramentas de pagar fatura, excluir transações, movimentar investimentos ou enviar mensagens externas nesta versão.

### 7.1 Dinheiro e comparações

- Usar Decimal no domínio do agente; ao ler REAL legado, converter a representação decimal e arredondar cada valor a duas casas com política `.plain`, testada.
- Transportar dinheiro como string decimal canônica ou centavos inteiros, nunca floats para o modelo calcular.
- Diferença percentual com base zero: retornar `null`/indicador de indisponibilidade no domínio, apresentar “sem base de comparação”; nunca dividir por zero.
- Separar despesas previstas, pagas e na fatura. Comparar os mesmos filtros nos dois meses.
- Uma fatura agregada manual e cobranças individuais podem coexistir; explicar que resultados refletem os lançamentos registrados. Não deduplicar ou corrigir automaticamente o banco.
- IDs de fatos carregam período/filtros e identificadores de origem, permitindo “Ver lançamentos”.

## 8. Propostas, confirmação e recuperação

Mover `AIExpenseView.Draft` para `ExpenseDraft` em modelo de domínio. Preservar valores candidatos, data opcional, categoria, pagamento e indicação de já incluído no saldo inicial.

Fluxo: descrição → extração → perguntas por campos ausentes → resumo → confirmar/corrigir/cancelar → mensagem de conclusão.

- Um campo ausente nunca pode parecer preenchido por um DatePicker com fallback `.now`.
- Corrigir cria uma nova revisão e invalida a confirmação anterior.
- Cartão e pagamentos seguem as regras atuais do app após o usuário confirmar o lançamento; não reativar a regra automática por dia de cobrança.
- Cada botão confirmar captura `proposalID` e `revision`, não a seleção atual da tela.
- Confirmação executada por controller, sem ferramenta acessível ao modelo.
- Em um único savepoint: reler proposta awaiting_confirmation, validar revisão e mês existente, gravar despesas, marcar committed e persistir recibo da operação.
- Segunda confirmação da mesma proposta retorna o recibo já registrado, sem novas despesas.
- Se a gravação falhar, rollback de tudo; proposta permanece confirmável e o chat mostra falha.
- Se a gravação funcionar e o refresh da UI falhar, mostrar “salvo, falha ao atualizar tela”; nunca induzir repetição da gravação.
- Ao restaurar backup ou remover o mês, propostas em memória são invalidadas/recarregadas antes de permitir confirmação.

## 9. Memória explícita do usuário

Começar com memórias aprovadas, sem extração automática silenciosa do histórico.

Tipos: `preference`, `goal`, `context`. Exemplos: preferência por respostas breves; objetivo de economizar para viagem; uso de uma categoria específica para um estabelecimento.

- Usuário pode clicar em “Salvar como memória” numa mensagem ou abrir Configurações → Assistente → Memória.
- Mostrar texto exato antes de salvar. Propostas de memória do modelo, se adicionadas depois, também exigirão revisão.
- `memory_key` identifica o assunto; atualização do mesmo assunto incrementa revision. Em conflito sem chave inequívoca, perguntar qual memória substituir; não decidir pela similaridade apenas.
- Guardar origem e datas. Nunca promover saldo, fatura atual ou previsão inferida a fato permanente.
- Memória não altera lançamentos nem categorias existentes. É contexto para respostas/propostas futuras.
- Editar memória remove o vetor antigo e agenda novo embedding. Esquecer exclui conteúdo e vetor e limpa caches/contextos pendentes; cancelar turnos que já capturaram a memória.
- Toggle “Usar memória nas respostas”. Desativado: não enviar nem buscar memórias; histórico da conversa continua funcionando.
- Preferências de tom não são instruções executáveis. Tratar conteúdo recuperado como dados delimitados, incluindo textos maliciosos armazenados em descrições.

## 10. Embeddings e busca semântica

Adicionar configuração separada `ollamaEmbeddingModel`, sem alterar `ollamaModel`. Escolher o modelo instalado pelo usuário; não baixar automaticamente modelos. Consultar `/api/tags` para seleção e registrar nome+digest.

`EmbeddingClient.embed(texts:) async throws -> [[Double]]` usa `POST /api/embed` e a mesma política de sessão/erros de rede. Esse endpoint tem contrato próprio; não enviar os campos `think` ou `format` da API de chat.

Validar quantidade de vetores, dimensão consistente, valores finitos e norma maior que zero. Validar resposta mesmo em HTTP 200. Timeout ou modelo ausente desativa apenas a busca vetorial; a conversa e a memória explícita continuam utilizáveis.

Persistência inicial: JSON de números em `vector_json`, visando simplicidade para volume pessoal. Não instalar extensão SQLite vetorial. Calcular cosseno em Swift, em tarefa fora do MainActor com snapshots imutáveis. Não acessar o handle SQLite nessa tarefa.

Indexar apenas memórias ativas na primeira entrega. Histórico completo fica disponível por conversa e busca textual; não indexar todas as transações/mensagens por padrão.

Busca:

1. Gerar embedding da pergunta com o mesmo modelo/digest/dimensão do índice ativo.
2. Descartar vetores de revision ou identidade de modelo divergentes.
3. Ordenar por cosseno; retornar até 5 acima de limiar configurado internamente.
4. Começar com limiar 0,60 como parâmetro provisório, calibrar com conjunto de exemplos; não tratar score como confiança factual.
5. Se embedding falhar, usar correspondência textual local e perfil explícito. Mostrar ausência de resultado quando aplicável; não inventar lembranças.

Modelo alterado: marcar índice antigo inválido e reindexar memórias em lotes de até 16, com progresso/cancelamento. Só publicar um vetor se revision atual ainda corresponder à que foi enviada ao modelo. Memória editada/apagada durante a chamada não pode reaparecer pelo retorno atrasado.

## 11. Etapas de implementação e critérios de conclusão

Executar em ordem. Cada etapa deve compilar e ter os testes específicos passando antes da próxima.

### Etapa A — persistência e modelos

1. Criar tipos de domínio e enums; extrair ExpenseDraft.
2. Adicionar tabelas e métodos de repositório, com queries parametrizadas.
3. Implementar ordem de mensagens e recuperação de turnos interrompidos.
4. Testar migração repetida, reopen, cascatas e preservação de dados financeiros.

Concluído quando histórico e proposta persistem em banco temporário e nenhuma regra financeira muda.

### Etapa B — conversa persistente

1. Mover estado/tarefas de AIExpenseView para AssistantController.
2. Criar controller acima das telas no ciclo de vida do app; injetar dependências.
3. Implementar seleção de conversa, nova conversa e cancelamento.
4. Exibir mensagens por tipo e manter propostas no chat.

Concluído quando trocar tela, fechar painel e reiniciar app não perde histórico nem duplica mensagens.

### Etapa C — personalidade e contexto

1. Criar persona versionada e preferências.
2. Implementar construtor de contexto com limites e relógio injetável.
3. Adicionar settings de nome e detalhe.
4. Testar ordem de autoridade das instruções e cortes sem JSON inválido.

Concluído quando o contexto é reproduzível e não inclui o banco inteiro.

### Etapa D — fatos financeiros e registry

1. Implementar consultas de leitura e cálculos Decimal.
2. Criar catálogo, enums dinâmicos e schemas de argumentos.
3. Implementar renderizadores de fatos e links para lançamentos.
4. Testar filtros, exclusões, meses distintos, base zero e IDs inválidos.

Concluído quando resultados coincidem com fixtures financeiras conhecidas, sem modelo.

### Etapa E — agente com ferramentas

1. Estender validador de schema com testes antes de usar novos keywords.
2. Implementar AgentDecisionTask e laço limitado.
3. Registrar tool runs; impedir resultado de turno cancelado.
4. Conectar consultas pelo compositor e sugestões iniciais.

Concluído quando transporte simulado executa pergunta → ferramenta → resposta com fatos corretos e limites comprovados.

### Etapa F — gravação confirmada

1. Conectar prepare_expenses ao fluxo existente.
2. Persistir revisão, confirmação e recibo idempotente.
3. Fazer commit financeiro e status da proposta na mesma transação.
4. Implementar recuperação depois de fechar e reabrir.

Concluído quando clique duplo, retry e crash após commit nunca duplicam despesas.

### Etapa G — memória explícita

1. Implementar CRUD e tela de memórias.
2. Implementar salvar mensagem como memória com revisão.
3. Incluir memórias ativas no contexto e toggle de uso.
4. Testar esquecimento, atualização, conflito e origem removida.

Concluído quando usuário consegue inspecionar/corrigir/apagar tudo que o assistente lembra.

### Etapa H — embeddings

1. Implementar cliente separado e configuração de modelo.
2. Indexar memórias em lotes; validar identidade e revision.
3. Implementar busca, limiar e fallback textual.
4. Testar modelos diferentes, falha de rede e edição concorrente com indexação.

Concluído quando consulta semanticamente relacionada recupera a memória correta e falhas de embeddings não bloqueiam o chat.

### Etapa I — acabamento e documentação

1. Revisar acessibilidade, teclado, auto-scroll e tamanho mínimo da janela.
2. Aplicar ocultação de valores no chat usando o mesmo estado das telas. Mensagens livres do usuário podem conter valores: no modo oculto, mascarar o corpo dessas mensagens e oferecer revelação explícita.
3. Atualizar README e docs/ai-architecture.md, incluindo backup, modelos, limites e comportamento offline.
4. Executar suíte completa, build release e validação visual.

## 12. Matriz mínima de testes

Criar arquivos separados: `AssistantRepositoryTests`, `AgentRunnerTests`, `FinancialFactsTests`, `AssistantProposalTests`, `MemoryServiceTests`, `EmbeddingTests`. Usar bancos temporários e transporte simulado. Não exigir servidor para a suíte padrão.

Casos obrigatórios:

- Reabrir conversa preserva ordem e marca tarefa incompleta como interrompida.
- Trocar mês durante resposta preserva destino capturado.
- Resposta inválida, ferramenta inexistente, campos extras e argumentos fora do escopo são rejeitados.
- Repetição de ferramenta e limite de chamadas encerram turno sem loop.
- Cancelar durante rede impede mensagem/efeito tardio.
- “Quanto gastei?” usa soma local, sem consultar lançamentos excluídos.
- Comparação com base zero não produz infinito/NaN.
- Texto malicioso em lançamento/memória não habilita ferramenta nem confirma proposta.
- Dupla confirmação grava uma vez; rollback não marca committed.
- Mês removido ou backup importado invalida proposta antiga.
- Memória apagada deixa de ser recuperada mesmo com embedding em andamento.
- Dimensões/digests diferentes nunca são comparados.
- Falha de embedding permite consulta financeira e resposta textual.
- `think: false` e schema obrigatório permanecem nos requests de conversa.

Teste de integração no servidor deve ser opcional por variável de ambiente, com dados fictícios. Medir latência e registrar modelo/digest. Não prometer desempenho antes de medir.

## 13. Validação manual e entrega

Roteiro em banco de teste, sem gravar no banco pessoal:

1. Abrir balão no Resumo e nas outras telas; conferir ícone, foco e clique.
2. Registrar gasto faltando data; responder “ontem”; conferir o resumo.
3. Corrigir, cancelar e confirmar outro gasto. Verificar recibo e total salvo uma única vez.
4. Fechar/reabrir painel e app; recuperar histórico e proposta pendente.
5. Perguntar por gastos de dois meses; conferir os fatos apresentados com os dados da fixture.
6. Salvar preferência, abrir nova conversa, recuperar e esquecer.
7. Desligar servidor: ler histórico local, observar erro recuperável e testar fallback de memória.
8. Trocar modelo de embeddings; verificar progresso e ausência de mistura de vetores.
9. Testar janela mínima, modo claro/escuro, reduzir transparência e ocultar valores.

Comandos finais:

```sh
swift test
./scripts/build-app.sh
git diff --check
git status --short
```

Esperar conclusão real de cada processo; preservar session_id quando o comando continuar em execução. Existência ou data do binário não substitui confirmar que build e assinatura terminaram com exit code zero.

Entregar resumo do que mudou, testes executados/pulados, evidências de validação visual e limitações conhecidas. Não afirmar que a UI foi validada apenas porque testes unitários passaram. Commit/push somente se autorizado no pedido de implementação.

## 14. Fora do escopo e expansão futura

Não implementar nesta entrega: backend, app móvel, sincronização, execução com app fechado, agendamentos financeiros, acesso à internet pelo agente, alteração autônoma de saldo, recomendação de investimentos, treinamento/fine-tuning, extração silenciosa de memória e indexação irrestrita de dados pessoais.

Se houver necessidade de múltiplos dispositivos ou execução contínua, migrar os contratos de repository/runner para um serviço no servidor. Essa evolução exige autenticação e política de sincronização dos dados financeiros; não é apenas mover o Ollama.

Referências oficiais para consultar ao implementar a integração:

- [Ollama — Structured outputs](https://docs.ollama.com/capabilities/structured-outputs)
- [Ollama — Tool calling](https://docs.ollama.com/capabilities/tool-calling)
- [Ollama — Embeddings](https://docs.ollama.com/capabilities/embeddings)
- [Ollama — API embed](https://docs.ollama.com/api/embed)
