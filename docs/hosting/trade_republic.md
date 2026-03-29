# Trade Republic and Sure

## Public API status

Trade Republic does **not** publish a documented, self-serve **official API** for third-party personal finance applications to pull portfolio history, per-instrument positions, and orders in the same way as providers integrated in Sure (e.g. Plaid, Enable Banking, Coinbase).

What exists in the ecosystem is mostly **unofficial** client libraries. They are not suitable for a production integration here: they can break without notice, may conflict with Trade Republic’s terms of use, and create security and compliance risk for self-hosters.

### Native connector in Sure (self-hosted, unofficial)

Sure includes a **Trade Republic** item under **Settings → Sync Providers**:

1. **Built-in login (default):** the app uses **headless Chromium** (via the [Ferrum](https://github.com/rubycdp/ferrum) gem) to obtain an AWS WAF token, then calls Trade Republic’s HTTP login API—same idea as Picsou’s tr-auth, without a separate Python service. You need a working Chrome/Chromium on the server (or container) where Rails runs.
2. **Optional external sidecar:** if you prefer [Picsou’s `services/tr-auth`](https://github.com/Zoeille/picsou-finance/tree/main/services/tr-auth) (FastAPI + Playwright), set `TRADE_REPUBLIC_TR_AUTH_URL` to its base URL, or enter that URL per connection in the UI.
3. Connect from the UI: SMS PIN flow, then link each **sub-portfolio** (PEA, CTO, cash, etc.) to a Sure account.

Portfolio data is read over Trade Republic’s **WebSocket** API (protocol v31), similar to Picsou’s Java adapter. Only **EUR-style sub-portfolio net values** are synced into Sure as balances; there is **no** per-order or per-ISIN history from this path. The API is **unofficial**, can break without notice, and may conflict with broker terms—use at your own risk.

### Community reference

[Picsou Finance](https://github.com/Zoeille/picsou-finance) documents the same patterns (tr-auth + WebSocket) and CSV fallbacks.

## Practical ways to use Sure with Trade Republic today

### 1. Open banking / aggregators (Europe)

In the EU, some **PSD2 / open banking** aggregators expose Trade Republic for **account information** (coverage varies by country and institution). Sure supports **Enable Banking** (and other connectors depending on your deployment). Check whether Trade Republic appears when you connect through your region’s flow.

This path typically gives **balances and transactions** comparable to a cash account, not always full **per-ISIN history** or **crypto lot** detail. Investment-specific charts depend on what the aggregator normalizes into Sure.

### 2. Brokerage / investment connectors

If Trade Republic is available through an **investment-focused** connector you have enabled (e.g. where your deployment supports it), create an **Investment** (or **Crypto**) account in Sure and map it to the synced institution. Sure will then:

- Store **holdings** and **trades** when the provider supplies them  
- Show **per-security** evolution through the usual **account balance** and **holdings** views for that account  

There is no separate “Trade Republic-only” chart type: the same investment account UI applies once data is present.

### 3. Manual investment account

Create an **Investment** or **Crypto** account, then add **trades** and **valuations** (or import via CSV if your workflow supports it). You still get **per-position** and **historical** views from Sure’s standard investment model.

## If Trade Republic ships an official API later

If Trade Republic releases a **documented, consent-based API** (OAuth, scoped keys, data dictionary for positions and instruments), a first-class connector could be added following the same patterns as other `*\_items` providers in this codebase (sync jobs, encrypted credentials, `AccountProvider` mapping).

Contributions should include:

- Link to **official** developer documentation  
- Clear **rate limits** and **data retention** behaviour  
- Tests and self-hosted configuration docs under `docs/hosting/`

## References

- [Trade Republic](https://traderepublic.com) — product and support pages  
- Sure provider docs: [Plaid](plaid.md), [Enable Banking](enable_banking.md) (examples of supported integration styles)
