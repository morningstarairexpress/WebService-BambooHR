package WebService::BambooHR::MappingValidator;

use 5.010;
use strict;
use warnings;
use Exporter 'import';
use Try::Tiny;

our @EXPORT_OK = qw( validate_mapping request_fields employee_value );

=head1 NAME

WebService::BambooHR::MappingValidator - check a field/table mapping against live BambooHR metadata

=head1 SYNOPSIS

    my $resolved = validate_mapping( $registry, $config );   # dies once, listing every problem

    my $bamboo = WebService::BambooHR->new(
        company       => $company, api_key => $key,
        custom_fields => request_fields( $resolved->{employee} ),    # logical name => numeric id
    );

    my $employee = $bamboo->employee($id);                            # or ->employee_list
    my $size     = employee_value( $employee, $resolved->{employee}{shirt_size} );

    my $rows = $tabular->rows_by_employee( $resolved->{tables}{equipment}{alias} );
    my $item = $row->field( $resolved->{tables}{equipment}{columns}{item} );

=head1 DESCRIPTION

An application names the BambooHR things it needs with I<logical names> of its own choosing, and says how to find each
one. This module resolves the whole mapping in one pass and reports every problem at once, so a mapping that has
drifted from the account's configuration fails loudly instead of returning nothing.

Config shape (the keys under C<employee_fields> and C<tables> are yours):

    employee_fields:                  # logical name => numeric id, alias or display name
      shirt_size: "Shirt Size"
      hired:      hireDate
    tables:
      equipment:                      # logical table name
        table_alias: customEquipment  # tables have no display name in the API: alias only
        columns:                      # resolved INSIDE that table, where display names are unique
          item:   "Item category"
          serial: "Serial #"

Returns

    { employee => { logical => { id, name, type, alias, column_aliases, keys } },
      tables   => { logical => { alias => '...', columns => { logical => { id, name, type, alias } } } } }

C<employee> and C<tables> are always present (possibly empty).

=head2 Why the value lookup takes a field record rather than an id

The same field can come back under different keys depending on the call (see F<docs/api-notes.md>):

    GET employees/ID?fields=9001     -> "9001"
    GET employees/ID?fields=ALIAS    -> the alias
    POST reports/custom (field 9001) -> an alias that /meta/fields may not list

L</employee_value> tries each key in C<< {keys} >>. Request fields by numeric id: aliases can contain C<#>, C<?>, C<,>,
C<(>, C<)>, C</>, C<*> and C<'>, none of which survive an unescaped C<?fields=a,b> query string.

=head2 validate_mapping( $registry, \%config )

Dies with every problem listed (one per line, prefixed C<  - >) or returns the structure above.

=cut

sub validate_mapping {
    my ( $registry, $config ) = @_;
    my ( %resolved, @errors );
    $resolved{employee} = {};
    $resolved{tables}   = {};

    my $emp = $config->{employee_fields} // {};
    for my $logical ( sort keys %$emp ) {
        my $label = $emp->{$logical};
        try   { $resolved{employee}{$logical} = $registry->lookup_field($label) }
        catch { push @errors, _fmt( "employee_fields.$logical", $label, $_ ) };
    }

    my $tables = $config->{tables} // {};
    for my $name ( sort keys %$tables ) {
        my $tcfg  = $tables->{$name} // {};
        my $alias = $tcfg->{table_alias};
        unless ( defined $alias && length $alias ) { push @errors, "tables.$name.table_alias: not set in config"; next }

        my $table;
        try   { $table = $registry->lookup_table($alias) }
        catch { push @errors, _fmt( "tables.$name.table_alias", $alias, $_ ) };
        next unless $table;    # one error for a bad table, not one per column

        $resolved{tables}{$name} = { alias => $table->{alias}, columns => {} };
        my $cols = $tcfg->{columns} // {};
        for my $logical ( sort keys %$cols ) {
            my $label = $cols->{$logical};
            try   { $resolved{tables}{$name}{columns}{$logical} = $registry->lookup_table_field( $table, $label ) }
            catch { push @errors, _fmt( "tables.$name.columns.$logical", $label, $_ ) };
        }
    }

    die "Field mapping validation failed (" . @errors . " error" . ( @errors == 1 ? '' : 's' ) . "):\n"
        . join( "\n", map {"  - $_"} @errors ) . "\n"
        if @errors;
    return \%resolved;
}

=head2 request_fields( \%resolved_employee )

C<< { logical => id } >>, for WebService::BambooHR's C<custom_fields>.

=cut

sub request_fields { my ($emp) = @_; return { map { $_ => $emp->{$_}{id} } keys %$emp } }

=head2 employee_value( $employee, $field_record )

The value of a resolved field from a L<WebService::BambooHR::Employee>, whichever key BambooHR used (see above).
C<$employee> only needs a C<custom($key)> method returning the value stored under a raw key.

=cut

sub employee_value {
    my ( $employee, $field ) = @_;
    for my $k ( @{ $field->{keys} // [ $field->{id} ] } ) {
        my $v = $employee->custom($k);
        return $v if defined $v;
    }
    return undef;
}

sub _fmt {
    my ( $path, $label, $err ) = @_;
    my $msg = ref($err) && $err->can('message') ? $err->message : "$err";
    $msg =~ s/\s+$//;
    return "$path ('$label'): $msg";
}

1;
