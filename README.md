<div align="center">
  <img src="Resources/AppIcon.png" alt="Finanças icon: an upward arrow inside an open circle" width="128" height="128">
  <h1>Finanças</h1>
  <p><strong>Your money, with clarity.</strong></p>
  <p>A native app to organize your month, track expenses, and plan what comes next.<br>No account, no server. Your data stays on your Mac.</p>
  <p>
    <img src="https://img.shields.io/badge/macOS-14%2B-184D3D?style=flat-square" alt="macOS 14 or later">
    <img src="https://img.shields.io/badge/interface-SwiftUI-184D3D?style=flat-square" alt="SwiftUI interface">
    <img src="https://img.shields.io/badge/data-local_SQLite-184D3D?style=flat-square" alt="Data in local SQLite">
  </p>
  <p><a href="#your-month-in-one-place">Features</a> · <a href="#start-here">How to run</a> · <a href="#build-the-app">Build</a> · <a href="#your-data">Data and backup</a></p>
</div>

---

## Your month in one place

| Area | What you track |
| --- | --- |
| **Summary** | Current balance, pending payments, card bill, expected salary, and spending by category. |
| **Expenses** | Recurring expenses, organized by category and copied into new months. |
| **Outflows** | One-off purchases and payments, with status filters. |
| **Income** | Salaries, extra income, and the next expected fixed income. |
| **Investments** | Funds, goals, contributions, withdrawals, and emergency reserve coverage. |
| **Settings** | Recurrences, local files, and backup import or export. |

### Always close at hand

Click the Finanças symbol in the menu bar to check your balance, pending payments, card bill, and next fixed income. You can also record an outflow or income there.

**Open Finanças** takes you to the full window. Closing the window keeps the menu bar panel available; to quit the app, choose **Quit Finanças** from the panel menu.

### An interface with room to breathe

Deep green, sandy tones, and a symbol of growth give the app its identity. On macOS 26 or later, buttons use native Liquid Glass; cards feature translucent materials. Earlier versions use compatible controls.

The app respects the macOS **Reduce transparency** preference. The eye button, available in the window and the menu bar panel, lets you hide amounts.

## Start here

To run the app, you need **macOS 14 or later**. To compile the current code, use **Xcode 26 or later**, with the macOS 26 SDK and command line tools selected.

From the project root:

```bash
swift run Financas
```

You can also open `Package.swift` in Xcode, select the **Financas** scheme, and press **⌘R**.

## Build the app

The script compiles the production version, includes the icon, and creates a locally signed app:

```bash
./scripts/build-app.sh
```

The result is at **`dist/Financas.app`**. To open it:

```bash
open dist/Financas.app
```

To build only the executable:

```bash
swift build -c release
```

It will be at `.build/release/Financas`. Distribution to other Macs requires proper signing and notarization; the script uses an *ad hoc* signature for local use.

## How balances work

The current balance starts from the amount you enter and tracks completed transactions:

- Received income and withdrawals increase the account balance.
- Paid expenses and investment contributions decrease the balance.
- Pending entries or those still on the card bill do not affect the balance until paid.
- Paying off the card bill moves items from **On the bill** to **Paid**, without creating another expense.

Recurring card expenses with a due day move to **On the bill** when the date arrives and the app checks the entries. PIX, debit, and automatic debit remain pending until payment is confirmed.

The emergency reserve is displayed in months of coverage, using the balance of the fund marked as the reserve and the selected month's fixed expenses.

## Your data

The SQLite database is at this path:

```text
~/Library/Application Support/Financas/financas.sqlite
```

In **Settings**, you can reveal the file in Finder, export a backup, or import a copy. **Importing replaces the current data.** The database and `.sqlite` backups are ignored by Git.

This is a personal project: the first launch creates the structure, default data, and funds with the opening balances defined in [`Database.swift`](Sources/Financas/Database.swift). It does not create months or cash transactions. Review these values before using the project for your own finances.

## Development

Interface in **SwiftUI**, charts with **Swift Charts**, macOS integration through **AppKit**, and local persistence in **SQLite**.

```bash
swift test
```

The icon is drawn in code. To regenerate the PNG and ICNS files used by the app:

```bash
swift scripts/generate-icon.swift
```

<div align="center">
  <br>
  <p><em>One month at a time.</em></p>
</div>
