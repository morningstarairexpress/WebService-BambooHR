package WebService::BambooHR::TabularData;

use 5.010;
use strict;
use warnings;
use Moo;
use JSON::MaybeXS qw( decode_json );

use WebService::BambooHR::TableRow;
use WebService::BambooHR::Exception;

=head1 NAME

WebService::BambooHR::TabularData - read BambooHR custom tables (writes are provided but untested)

=head1 SYNOPSIS

    my $bamboo  = WebService::BambooHR->new( company => 'acme', api_key => $key );
    my $tabular = WebService::BambooHR::TabularData->new( user_agent => $bamboo );

    my $by_emp  = $tabular->rows_by_employee('customEquipment');          # one request for every employee
    my @rows    = $tabular->get_rows( 111, 'customEquipment' );           # one employee
    my $changes = $tabular->changed_rows( 'customEquipment', '2026-09-01T00:00:00Z' );

=head1 DESCRIPTION

C<user_agent> is any object providing C<_get> (and, for writes, C<_post_json>/C<_delete>): the
L<WebService::BambooHR> client itself, because L<WebService::BambooHR::UserAgent> is a Moo::Role.

What the API was observed to do (see F<docs/api-notes.md>):

=over 4

=item * Every table endpoint honours C<Accept: application/json>, so no XML parsing is needed.

=item * C<GET employees/all/tables/{table}> returns every employee's rows in one response, so a full snapshot
costs one request per table rather than one per employee.

=item * Rows are keyed by column alias; see L<WebService::BambooHR::TableRow>.

=item * C<changed/tables> responds with C<< { employees => { ID => { lastChanged, rows => [...] } }, table } >>.
Those rows carry no row id. BambooHR documents the endpoint as employee-level: any change to the employee
returns all of that employee's rows.

=item * A table whose alias contains an apostrophe returned an HTML 404 on every endpoint, raw or percent-encoded,
while one containing a hyphen worked. Path segments are still percent-encoded here as ordinary URL hygiene, but
encoding does B<not> rescue such a table: avoid punctuation in table names.

=back

=cut

has 'user_agent' => ( is => 'ro', required => 1 );

=head2 get_rows( $employee_id, $table_alias )

List of L<WebService::BambooHR::TableRow>; empty if the employee has none (BambooHR answers C<[]>).

=cut

sub get_rows {
    my ( $self, $employee_id, $table ) = @_;
    my $r = $self->user_agent->_get( 'employees/' . _seg($employee_id) . '/tables/' . _seg($table) );
    return $self->_rows( $r->{content}, "employees/$employee_id/tables/$table", $employee_id );
}

=head2 all_rows( $table_alias )

Every row for every employee, from C<employees/all/tables/{table}>.

=cut

sub all_rows {
    my ( $self, $table ) = @_;
    my $r = $self->user_agent->_get( 'employees/all/tables/' . _seg($table) );
    return $self->_rows( $r->{content}, "employees/all/tables/$table", undef );
}

=head2 rows_by_employee( $table_alias )

C<< { employee_id => [ TableRow, ... ] } >> built from L</all_rows>.

=cut

sub rows_by_employee {
    my ( $self, $table ) = @_;
    my %by;
    push @{ $by{ $_->employee_id } }, $_ for $self->all_rows($table);
    return \%by;
}

=head2 changed_rows( $table_alias, $since )

C<< { employee_id => { last_changed => '...', rows => [ TableRow, ... ] } } >> for every employee changed since
C<$since> (ISO 8601). An empty result may arrive as C<{}>, C<[]> or a missing C<employees>: all mean "no changes".

On the account probed, the feed was bursty: on one day a bulk job touched about half of all employees at once, and
on ordinary days it listed every employee anyone had edited. Either way it says nothing about whether a I<particular
table> changed, because any change to the employee counts. To detect changes in one table, prefer
L</rows_by_employee> plus a local hash comparison.

=cut

sub changed_rows {
    my ( $self, $table, $since ) = @_;
    my $path = 'employees/changed/tables/' . _seg($table) . '?since=' . _seg($since);
    my $r    = $self->user_agent->_get($path);
    my $d    = decode_json( $r->{content} );
    _bad_shape( $path, 'a JSON object' ) unless ref $d eq 'HASH';

    my $e = $d->{employees};
    return {} unless defined $e;                                       # nothing changed
    return {} if ref $e eq 'ARRAY' && !@$e;                            # PHP serialises an empty map as []
    _bad_shape( $path, '"employees" as an object keyed by employee id' ) unless ref $e eq 'HASH';
    return {} unless %$e;

    my %out;
    for my $eid ( keys %$e ) {
        my $v = $e->{$eid};
        _bad_shape( $path, "employees.$eid as { lastChanged, rows }" ) unless ref $v eq 'HASH' && ref $v->{rows} eq 'ARRAY';
        $out{$eid} = {
            last_changed => $v->{lastChanged},
            rows         => [ map { WebService::BambooHR::TableRow->new( employee_id => "$eid", fields => { %$_ } ) } @{ $v->{rows} } ],
        };
    }
    return \%out;
}

# ---------------------------------------------------------------------------------------------- writes (untested)

=head2 add_row / update_row / delete_row

Provided for completeness. They have B<not> been exercised against a real tenant (they were written for completeness) and
should be treated as experimental until they have been.

=cut

sub add_row {
    my ( $self, $employee_id, $table, $fields ) = @_;
    my $r = $self->user_agent->_post_json( 'employees/' . _seg($employee_id) . '/tables/' . _seg($table), $fields );
    my $location = $r->{headers}{location} // '';
    return $1 if $location =~ m{/tables/[^/]+/([^/]+)$};

    my @caller = caller(0);
    WebService::BambooHR::Exception->throw({
        method => __PACKAGE__ . '::add_row', message => "API didn't return new row id in Location header",
        code => 500, reason => 'Internal server error', filename => $caller[1], line_number => $caller[2],
    });
}

sub update_row {
    my ( $self, $employee_id, $table, $row_id, $fields ) = @_;
    return $self->user_agent->_post_json( 'employees/' . _seg($employee_id) . '/tables/' . _seg($table) . '/' . _seg($row_id), $fields );
}

sub delete_row {
    my ( $self, $employee_id, $table, $row_id ) = @_;
    $self->user_agent->_delete( 'employees/' . _seg($employee_id) . '/tables/' . _seg($table) . '/' . _seg($row_id) );
    return 1;    # _request throws on any non-2xx
}

# ---------------------------------------------------------------------------------------------- internals

sub _rows {
    my ( $self, $json, $path, $employee_id ) = @_;
    return () unless defined $json && length $json;
    my $d = decode_json($json);
    _bad_shape( $path, 'a JSON array of row objects' ) unless ref $d eq 'ARRAY';

    return map {
        my %f  = %$_;
        my $id = delete $f{id};
        my $ee = delete $f{employeeId};
        WebService::BambooHR::TableRow->new(
            row_id      => defined $id ? "$id" : undef,
            employee_id => defined $ee ? "$ee" : defined $employee_id ? "$employee_id" : '',
            fields      => \%f,
        );
    } @$d;
}

sub _bad_shape {
    my ( $path, $expected ) = @_;
    my @c = caller(1);
    WebService::BambooHR::Exception->throw({
        method => $c[3] // __PACKAGE__, message => "unexpected response for $path: expected $expected",
        code => 502, reason => 'Unexpected response shape', filename => $c[1] // '(unknown)', line_number => $c[2] // 0,
    });
}

# Percent-encode a path segment / query value (unreserved characters only are left alone).
sub _seg { my ($s) = @_; $s //= ''; $s =~ s/([^A-Za-z0-9\-\._~])/sprintf('%%%02X', ord($1))/ge; return $s }

1;
