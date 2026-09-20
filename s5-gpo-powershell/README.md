# S5 — Group Policy and PowerShell automation

> **Status: in progress.** Of the three GPOs and two scripts this week calls for,
> one GPO exists and applies. This file documents what is built and what is not;
> it is not a claim that the week is finished.

`lab.local` · GPOs at domain and OU level

Goal: enforce three policies on the domain built in S4, and automate the two tasks a
sysadmin repeats most — creating users and auditing accounts.

---

## 1. What exists (`Get-GPO -All`, 2026-09-19)

| GPO | Linked to | Type | Status |
|---|---|---|---|
| `Default Domain Policy` | domain root | built-in | account/password policy lives here <!-- TODO: confirm the values you set --> |
| `Default Domain Controllers Policy` | `OU=Domain Controllers` | built-in | untouched |
| `GPO-DriveMaps-Departamentos` | `OU=Departamentos` | **Preference** (GPP) | applies on the client — verified with `gpresult /r` |

Not built yet: the USB lockdown policy, and the fine-grained password policy (PSO)
for `GG_IT`.

### Verified on the client

`gpresult /r` on `WINCLIENT` (Windows 10 Pro 22H2, member workstation), user `LAB\1`:

- Applied: `GPO-DriveMaps-Departamentos`. Nothing filtered out except the local
  policy (empty).
- Policies retrieved from `WIN-N4T58SARLC4.lab.local`, i.e. from DC1.
- **The user is in no `GG_` group.** The security-group list contains only built-in
  identities (`Usuarios`, `Usuarios autenticados`, …). If the drive mapping uses
  item-level targeting on `GG_Oficina`, it is applying the GPO but mapping nothing.
  <!-- TODO: add the user to its department group, log off/on (a token only refreshes
       at logon), and re-run gpresult. Then paste the "Applied GPOs" block here. -->
- Last applied 2026-09-08, read on 2026-09-19 — the client had not refreshed in
  11 days. Re-run after `gpupdate /force` + logon before using this as evidence.
- The user is named `1`. Placeholder accounts are fine while building; the week's
  deliverable is 10–15 accounts with realistic names, created by script (§2).

---

## 2. Design notes (why, not how)

These are the decisions the remaining work has to respect.

- **Account policy belongs at the domain root, never on an OU.** Password and
  lockout settings are read from the GPO linked to the domain; the same settings in
  an OU-linked GPO are silently ignored for domain accounts. Per-group exceptions
  are done with a **Fine-Grained Password Policy (PSO)** applied to a global group,
  with a precedence value — not with another GPO.
- **Drive mapping is a Preference; USB lockdown is a Policy.** Policies write to four
  reserved registry keys, grey out the UI and **revert** when the GPO is unlinked.
  Preferences write anywhere, stay user-editable and **tattoo** — unlink the GPO and
  the mapped drive is still there. Which one you used decides how you clean up.
- **Security filtering needs `Domain Computers` to keep Read.** If *Authenticated
  Users* is removed so a GPO can be filtered to a group, since MS16-072 the computer
  account is what retrieves user policies — drop its Read and the GPO applies to
  nobody. This is the number-one cause of a "filtered GPO that does nothing".
- **Refresh timing.** Every 90 min + 0–30 random on members, 5 min on DCs.
  `gpupdate /force` recalculates, but drive maps, folder redirection and software
  installation only take effect at **logon or reboot**.
- **Computer policies need computer objects in an OU.** See the S4 note: the client
  is in `CN=Computers`, and GPOs cannot be linked to a container.

### How it gets verified

| Tool | Shows |
|---|---|
| `gpresult /r` as the target user, on the client | which GPOs applied, and which were filtered out **and why** |
| `gpresult /h report.html` | the same, plus the resulting settings |
| `rsop.msc` | resultant set of policy |
| Group Policy Modeling (GPMC) | "what would happen if I moved this user to that OU" |
| Event Viewer → *Applications and Services Logs → Microsoft → Windows → GroupPolicy → Operational* | processing errors |

---

## 3. PowerShell — not written yet

Mental model: Bash passes text, PowerShell passes **objects**. You never parse with
`grep`/`awk`; you access properties. Three cmdlets make the module self-teaching:
`Get-Command -Module ActiveDirectory`, `Get-Help <cmdlet> -Examples`, and
`<object> | Get-Member`.

### Script 1 — bulk-create users from CSV

Requirements: read a CSV, resolve each row's department to an OU, create the user,
add it to its global group, skip rows that already exist, log failures, don't abort
on one bad row.

Decisions to make before typing:
- Department → OU as a **hashtable** at the top of the script, not chained `if`s: an
  OU change must not touch the logic. A missing key returns `$null` silently —
  check with `.ContainsKey()`.
- Derive the group name (`"GG_$($row.Departamento)"`) instead of keeping a second
  mapping table; one source of truth can't drift.
- Existence check with **`-Filter`, never `-Identity`**: `-Identity` throws when the
  user doesn't exist, so the "check" is what crashes the script.
- `try { … -ErrorAction Stop } catch { … }` — AD cmdlet errors are non-terminating,
  and `catch` never fires without `-ErrorAction Stop`.
- Build the `$params` hashtable **inside** the loop and splat it; built outside, it
  carries the previous user's values forward.
- The initial password must satisfy the domain policy from §1, or all ten users fail
  with a generic constraint-violation error that never mentions the password.

### Script 2 — account audit

`Search-ADAccount -AccountInactive -TimeSpan 90.00:00:00 -UsersOnly`, `-LockedOut`,
`-PasswordExpired`; export to CSV.

- `-Properties` is not optional: `Get-ADUser` returns ~10 properties and
  `LastLogonDate` is not one of them — the column comes back empty with no error.
- `-Filter` runs on the DC, `Where-Object` pulls everything to the client first.
  Irrelevant with 15 users, the difference between one second and minutes at 5 000.
- `LastLogonDate` is `lastLogonTimestamp` converted: replicated, but up to 14 days
  stale. `lastLogon` is exact but **not replicated** — each DC has its own value,
  which matters here because this domain has two DCs.
- `Export-Csv -NoTypeInformation -Encoding UTF8`.

<!-- TODO: write both scripts, put them in scripts/ with a sample users.csv (fake
     names), then replace this section with what they actually do. -->

---

## 4. Remaining for this week

1. Add the users to their `GG_` groups; re-verify with `gpresult` after a logon.
2. Create `OU=Equipos`, move the client, link the USB policy there.
3. Confirm (or set) the account policy in `Default Domain Policy` and record the values.
4. `PSO-IT-Admins` on `GG_IT`, min length 15, precedence 10.
5. Write both scripts; create the real 10–15 users with script 1.
6. One screenshot per item as evidence.
