---
name: domain-scout
description: Use when asked to find, check, shortlist or buy a domain name, or to set up DNS records for one (GitHub Pages, Vercel, Netlify, email). Works with the Namecheap MCP when it is connected and falls back to manual steps when it is not.
---

# domain-scout

Find a domain, shortlist it, and wire up DNS. Costs money and can take a live site
offline, so the confirmation rules at the bottom are not optional.

## Step 0: which mode

Look for Namecheap tools in your tool list (names contain `Namecheap`, such as
`domains_check_availability`, `dns_records_get`, `dns_records_save`). They may be
deferred: search for them before deciding they are missing.

- **Tools found: API mode.** Use the steps below.
- **No tools: manual mode.** Say so in one line, then use the manual column. Do not
  pretend to have checked anything. If the person wants API mode, tell them to
  connect the Namecheap MCP (in claude.ai connectors, or their own MCP config)
  and start a new session.

## Steps

1. **Brainstorm.** From the project idea, produce 20 to 30 candidates across a few
   TLDs (`.com`, `.app`, `.io`, `.dev`). Short, easy to say, easy to spell.
2. **Check availability.**
   - API mode: one batch call to `domains_check_availability`. Drop the taken ones.
   - Manual mode: `whois <domain>` or `dig +short NS <domain>` in Bash. No NS
     records or a "no match" whois usually means free. Report it as **likely
     available**, never "available": only a registrar can confirm.
3. **Shortlist.** Show the best 5 to 10: name, TLD, price if known, and one line on
   why. Flag obvious trademark or brand clashes; availability is not clearance.
4. **Buy.**
   - API mode: prefer `domain_purchase_link` so the person pays themselves. Use
     `domain_register` only if they explicitly say to register it.
   - Manual mode: give the registrar search link for each shortlisted name.
5. **DNS.** Once the person owns the domain:
   - API mode: `dns_records_get` first, show the current records, then
     `dns_records_save` with the new set. Show a diff before saving.
   - Manual mode: print the records as a table to paste into the registrar.
   - Afterwards verify with `dig +short <name> <type>`; DNS can take minutes to
     hours to propagate, so say so rather than calling a stale answer a failure.

## DNS recipes

| Target | Records |
|---|---|
| GitHub Pages (apex) | four `A` records: `185.199.108.153`, `185.199.109.153`, `185.199.110.153`, `185.199.111.153`; `www` `CNAME` to `<user>.github.io`; add the domain in the repo's Pages settings |
| Vercel | apex `A` `76.76.21.21`, `www` `CNAME` `cname.vercel-dns.com` (or use their nameservers) |
| Netlify | apex `A` `75.2.60.5` or their nameservers, `www` `CNAME` to `<site>.netlify.app` |
| Email (any host) | `MX` records and the `SPF` (`TXT`) and `DKIM` records exactly as the mail provider gives them |

These values change over time. If you are not sure, tell the person to confirm them
in the host's current docs before saving.

## Confirm first

- **Registering a domain** spends money and cannot be undone. Show the exact name and
  price, and wait for a yes.
- **`dns_records_save`** can replace existing records. Read first, show the diff, wait.
- **`domain_set_nameservers`** can take a live site offline. Warn, wait.
- **`contacts_save`** touches personal data. Never create or change contacts unasked.
