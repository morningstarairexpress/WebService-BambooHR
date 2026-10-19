package WebService::BambooHR::TableRow;

use 5.010;
use strict;
use warnings;
use Moo;

=head1 NAME

WebService::BambooHR::TableRow - one row of a BambooHR custom table

=head1 DESCRIPTION

Value object. What the API was observed to return (see F<docs/api-notes.md>):

=over 4

=item * C<GET employees/{id}/tables/{table}> and C<employees/all/tables/{table}> return an array of flat
objects keyed by the table I<column alias> (e.g. C<customAssetcategory>), plus C<id> and C<employeeId>.
Those two are numbers for custom tables but strings for standard tables such as C<jobInfo>; this class
stores both as strings.

=item * C<employees/changed/tables/{table}> rows carry neither C<id> nor C<employeeId>, so C<row_id> is C<undef>.

=item * Empty values arrive as C<null> or as C<""> interchangeably; see L</normalized_fields>.

=back

C<fields> holds only the column values (C<id>/C<employeeId> are lifted out).

=cut

has 'row_id'      => ( is => 'ro', default => sub { undef } );
has 'employee_id' => ( is => 'ro', required => 1 );
has 'fields'      => ( is => 'ro', default => sub { {} } );

=head2 field( $column )

C<$column> is a column alias, or a hashref with an C<alias> (and optionally C<id>), such as the entries
L<WebService::BambooHR::MappingValidator/validate_mapping> returns under C<< {tables}{NAME}{columns} >>.

=cut

sub field {
    my ( $self, $column ) = @_;
    $column = $column->{alias} // $column->{id} if ref $column eq 'HASH';
    return undef unless defined $column;
    return $self->fields->{$column};
}

=head2 normalized_fields

Copy of C<fields> with C<""> turned into C<undef>, so hashing/diffing treats the two spellings of "empty" alike.

=cut

sub normalized_fields {
    my $self = shift;
    return { map { $_ => ( defined $self->fields->{$_} && $self->fields->{$_} ne '' ? $self->fields->{$_} : undef ) } keys %{ $self->fields } };
}

sub to_request_body { my $self = shift; return { %{ $self->fields } } }

1;
