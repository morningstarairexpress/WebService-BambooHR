# Fixtures

**Every name, id, alias and value here is invented** (a fictional account called "Acme Test"). What is real is the
*shape* and the *quirks* the BambooHR API was observed to have; each is listed below and exercised by a test.
Nothing in this directory comes from a real account.

| file | what it models | quirks it preserves |
|---|---|---|
| `meta-fields.json` | `GET /v1/meta/fields` | ids are numbers, or **strings** for sub-fields (`"9100.6"`); two fields named `Hire Date`, two named `Job Title`, two `Comments`, two `Effective Date`; two fields sharing an alias (`employmentHistoryStatus`); a name with a **trailing space** and one with **doubled spaces**; two names differing only in whitespace; punctuation in aliases (`customNotes*optional*`, `customGLCode(New)`); a deprecated field; **one id listed twice** with two names and two aliases (a renamed field); table columns listed here without their alias |
| `meta-tables.json` | `GET /v1/meta/tables` | tables have an alias and **no display name**; alias `date` shared by several tables; `#` in a column alias; a column alias that exists only here (`custom#ofItems`); collision suffixes (`customEffectiveDate3`, `...4`); a hyphen in a table alias (works) and an apostrophe in one (404s) |
| `rows-*.json` | `GET employees/{id}/tables/{t}`, `employees/all/tables/{t}` | rows keyed by **column alias**; `id`/`employeeId` are numbers for custom tables and **strings** for standard tables; empty is `null` or `""` |
| `changed-tables-customEquipment.json` | `GET employees/changed/tables/{t}` | `{ employees: { ID: { lastChanged, rows } }, table }`; rows carry no `id` or `employeeId` |
| `employee-by-id.json`, `employee-by-alias.json`, `report-custom.json` | `GET employees/{id}?fields=...` and `POST reports/custom` | the **same field** arrives under its id, its alias, or an alias that `/meta/fields` does not list, depending on the call |
| `meta-lists.json` | `GET /v1/meta/lists` | entry keys `fieldId, id, manageable, multiple, name, options`; option keys `archived, archivedDate, createdDate, id, manageable, name`. **The values of `archived` were never captured**: `yes`/`no` here is an assumption |
| `photo-11634.jpg` | upstream's own test fixture | unrelated |
