# WebService::BambooHR (fork with custom-field and custom-table support)

A fork of [neilbowers/WebService-BambooHR](https://github.com/neilbowers/WebService-BambooHR) 0.07. Upstream covers employees,
photos and change lists. This fork adds what is needed to work with **custom fields, custom tables and list options**, whose ids and
aliases differ from account to account.

This repository is a **general-purpose BambooHR client library**. It contains no application, no account-specific configuration and no
account data; applications use it as a dependency. See `docs/api-notes.md` for the API behaviour it is built around.

## What this fork adds

| | |
|---|---|
| `custom_fields` | per-instance mapping of *your* names to BambooHR field ids; `employee()`, `employee_list()` accept those names; `Employee->custom($name_or_id)` reads values whose keys are not standard fields |
| `UserAgent` | `_request`, `_delete`, `_post_json` helpers; `_employee_record` no longer writes unaliased fields under a stale id |
| `FieldRegistry` | turns the labels in your configuration into ids and aliases, using the account's own `/meta/fields` and `/meta/tables`; ambiguity is an error, never a silent pick |
| `MappingValidator` | resolves a whole mapping (employee fields, any number of tables and their columns) in one pass and reports every problem at once |
| `TabularData`, `TableRow` | read custom tables: one employee, or every employee in one request; the change feed (writes are provided but untested) |
| `ListOptions` | the selectable options of list fields (`/meta/lists`) |

```perl
use WebService::BambooHR;
use WebService::BambooHR::FieldRegistry;
use WebService::BambooHR::MappingValidator qw( validate_mapping request_fields employee_value );
use WebService::BambooHR::TabularData;

my $bamboo   = WebService::BambooHR->new( company => 'acme', api_key => $key );
my $registry = WebService::BambooHR::FieldRegistry->new( user_agent => $bamboo )->load;
my $map      = validate_mapping( $registry, {
    employee_fields => { shirt => 'Shirt Size' },
    tables => { equipment => { table_alias => 'customEquipment', columns => { category => 'Item category' } } },
} );

my $client = WebService::BambooHR->new( company => 'acme', api_key => $key, custom_fields => request_fields( $map->{employee} ) );
my $person = $client->employee($id);
my $size   = employee_value( $person, $map->{employee}{shirt} );

my $by_employee = WebService::BambooHR::TabularData->new( user_agent => $client )->rows_by_employee( $map->{tables}{equipment}{alias} );
```

## Tests

    cpanm --installdeps .
    prove -l t/01-require.t t/10* t/20* t/21* t/22* t/23* t/30* t/31*

The fixtures in `t/data` are invented (a fictional account) and reproduce the API's shapes and quirks: see `t/data/README.md`.
Upstream's `t/02`-`t/05` need network access to its public sandbox and are independent of this work.

## Status and honest limits

Tested against fixtures. Read behaviour was observed against one real account; writes were never run against a real account; the
values of a list option's `archived` flag were not captured. `docs/api-notes.md` lists what is verified and what is not.

## Credit and licence

The `custom_fields` option name comes from ferki's pull request #5 on the upstream repository; the implementation here is different.
Same licence as upstream (Perl 5): see the module POD.
