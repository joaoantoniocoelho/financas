<div align="center">
  <img src="Resources/AppIcon.png" alt="Ícone do Finanças: seta ascendente em um círculo aberto" width="128" height="128">
  <h1>Finanças</h1>
  <p><strong>Seu dinheiro, com clareza.</strong></p>
  <p>Um app nativo para organizar seu mês, acompanhar gastos e planejar o que vem depois.<br>Sem conta, sem servidor. Seus dados ficam no seu Mac.</p>
  <p>
    <img src="https://img.shields.io/badge/macOS-14%2B-184D3D?style=flat-square" alt="macOS 14 ou superior">
    <img src="https://img.shields.io/badge/interface-SwiftUI-184D3D?style=flat-square" alt="Interface em SwiftUI">
    <img src="https://img.shields.io/badge/dados-SQLite_local-184D3D?style=flat-square" alt="Dados em SQLite local">
  </p>
  <p><a href="#o-seu-mês-em-um-lugar">Recursos</a> · <a href="#comece-por-aqui">Como executar</a> · <a href="#gere-o-app">Build</a> · <a href="#seus-dados">Dados e backup</a></p>
</div>

---

## O seu mês em um lugar

| Área | O que você acompanha |
| --- | --- |
| **Resumo** | Saldo atual, pendências, fatura, salário previsto e gastos por categoria. |
| **Gastos** | Despesas recorrentes, organizadas por categoria e copiadas para os novos meses. |
| **Saídas** | Compras e pagamentos pontuais, com filtros por status. |
| **Entradas** | Salários, rendas extras e previsão da próxima entrada fixa. |
| **Investimentos** | Fundos, objetivos, aportes, resgates e cobertura da reserva de emergência. |
| **Configurações** | Recorrências, arquivos locais e importação ou exportação de backup. |

### Sempre por perto

Clique no símbolo do Finanças na barra de menus para consultar o saldo, as pendências, a fatura e a próxima entrada fixa. Você também pode registrar uma saída ou entrada por ali.

**Abrir Finanças** leva à janela completa. Fechar a janela mantém o painel da barra de menus disponível; para sair do app, escolha **Encerrar Finanças** no menu do painel.

### Uma interface com espaço para respirar

Verde profundo, tons de areia e um símbolo de crescimento dão identidade ao app. No macOS 26 ou superior, os botões usam Liquid Glass nativo; os cartões apresentam materiais translúcidos. Versões anteriores usam controles compatíveis.

O app respeita a preferência **Reduzir transparência** do macOS. O botão de olho, disponível na janela e no painel da barra de menus, permite ocultar os valores.

## Comece por aqui

Para executar, você precisa do **macOS 14 ou superior**. Para compilar o código atual, use **Xcode 26 ou superior**, com o SDK do macOS 26 e as ferramentas de linha de comando selecionadas.

Na raiz do projeto:

```bash
swift run Financas
```

Você também pode abrir `Package.swift` no Xcode, selecionar o esquema **Financas** e pressionar **⌘R**.

## Gere o app

O script compila a versão de produção, inclui o ícone e cria o aplicativo com assinatura local:

```bash
./scripts/build-app.sh
```

O resultado fica em **`dist/Financas.app`**. Para abri-lo:

```bash
open dist/Financas.app
```

Para gerar apenas o executável:

```bash
swift build -c release
```

Ele estará em `.build/release/Financas`. A distribuição para outros Macs exige assinatura e notarização apropriadas; o script usa uma assinatura *ad hoc* para uso local.

## Como os saldos funcionam

O saldo atual parte do valor informado e acompanha as movimentações realizadas:

- Entradas recebidas e resgates aumentam o saldo da conta.
- Gastos pagos e aportes em investimentos diminuem o saldo.
- Lançamentos pendentes ou ainda na fatura não alteram o saldo até serem pagos.
- Quitar a fatura muda os itens de **Na fatura** para **Pago**, sem criar outra despesa.

Recorrências de cartão com dia de vencimento passam para **Na fatura** quando a data chega e o app verifica os lançamentos. PIX, débito e débito automático permanecem pendentes até a confirmação do pagamento.

A reserva de emergência é exibida em meses de cobertura, usando o saldo do fundo marcado como reserva e os gastos fixos do mês selecionado.

## Seus dados

O banco SQLite fica neste caminho:

```text
~/Library/Application Support/Financas/financas.sqlite
```

Em **Configurações**, você pode revelar o arquivo no Finder, exportar um backup ou importar uma cópia. **A importação substitui os dados atuais.** O banco e os backups `.sqlite` são ignorados pelo Git.

Este é um projeto de uso pessoal: a primeira execução cria a estrutura, os dados padrão e os fundos com saldos iniciais definidos em [`Database.swift`](Sources/Financas/Database.swift). Não cria meses nem movimentações de caixa. Revise esses valores antes de usar o projeto para suas próprias finanças.

## Desenvolvimento

Interface em **SwiftUI**, gráficos com **Swift Charts**, integração com o macOS em **AppKit** e persistência local em **SQLite**.

```bash
swift test
```

O ícone é desenhado por código. Para regenerar os arquivos PNG e ICNS usados pelo app:

```bash
swift scripts/generate-icon.swift
```

<div align="center">
  <br>
  <p><em>Um mês de cada vez.</em></p>
</div>
