# Trade Republic and Sure

## Public API status

Trade Republic does **not** publish a documented, self-serve **official API** for third-party personal finance applications to pull portfolio history, per-instrument positions, and orders in the same way as providers integrated in Sure (e.g. Plaid, Enable Banking, Coinbase).

What exists in the ecosystem is mostly **unofficial** client libraries. They are not suitable for a production integration here: they can break without notice, may conflict with Trade Republic’s terms of use, and create security and compliance risk for self-hosters.

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
