package WebService::BambooHR::ListOptions;

use 5.010;
use strict;
use warnings;
use Moo;
use JSON::MaybeXS qw( decode_json );

use WebService::BambooHR::Exception::FieldNotFound;

=head1 NAME

WebService::BambooHR::ListOptions - the selectable options of BambooHR list fields

=head1 SYNOPSIS

    my $lists  = WebService::BambooHR::ListOptions->new( user_agent => $bamboo );
    my @labels = $lists->labels( $resolved->{tables}{equipment}{columns}{category}{id} );
    # ( 'Laptop', 'Phone', 'Badge' )

=head1 DESCRIPTION

C<GET /v1/meta/lists> returns one entry per list field. What was B<observed> (see F<docs/api-notes.md>):

=over 4

=item * the response is an array of objects with the keys C<fieldId>, C<id>, C<manageable>, C<multiple>, C<name>
and C<options> (some entries also have C<alias>);

=item * each option is an object with the keys C<id>, C<name>, C<archived>, C<archivedDate>, C<createdDate> and
C<manageable>;

=item * a list is matched to a field by C<fieldId>; the entry's own C<id> is a different number space.

=back

The values of C<archived> were B<not> captured. This class treats C<yes>, C<true> and C<1> (any case) as archived.
If a real value looks different, an archived option would be listed as active: check this against your account.
A bare string option, or a C<value> key in place of C<name>, is also accepted. If an option has no usable label the
lookup dies naming the keys it saw, rather than returning an empty list.

Labels are returned trimmed and with internal whitespace collapsed, because BambooHR display names carry stray
spaces (see L<WebService::BambooHR::FieldRegistry>).

=cut

has 'user_agent' => ( is => 'ro', required => 1 );
has '_lists'     => ( is => 'rw', default => sub { undef } );

=head2 options_for( $field_id )

Arrayref of C<< { label, archived } >> in the order BambooHR returns them. Throws FieldNotFound if no list
belongs to the field, or if more than one does.

=cut

sub options_for {
    my ( $self, $field_id ) = @_;
    my @hit = grep { _entry_key($_) eq "$field_id" } @{ $self->_load };

    $self->_throw( "no BambooHR list has fieldId '$field_id' (is it a list-type field?)", 404, 'Not Found', $field_id )
        unless @hit;
    $self->_throw( "more than one BambooHR list claims fieldId '$field_id'", 409, 'Ambiguous', $field_id )
        if @hit > 1;

    my $opts = $hit[0]{options};
    $self->_throw( "list for field '$field_id' has no 'options' array (keys seen: " . join( ',', sort keys %{ $hit[0] } ) . ')',
        502, 'Unexpected response shape', $field_id )
        unless ref $opts eq 'ARRAY';

    my @out;
    for my $o (@$opts) {
        my ( $label, $archived );
        if ( ref $o eq 'HASH' ) {
            $label    = $o->{name} // $o->{value};
            $archived = ( $o->{archived} // '' ) =~ /^(?:yes|true|1)$/i ? 1 : 0;
        }
        elsif ( !ref $o ) { $label = $o; $archived = 0 }
        $self->_throw( "an option of list '$field_id' has no usable label (keys seen: "
              . ( ref $o eq 'HASH' ? join( ',', sort keys %$o ) : ref($o) || 'scalar' ) . ')', 502, 'Unexpected response shape', $field_id )
            unless defined $label && length $label;
        push @out, { label => _clean($label), archived => $archived };
    }
    return \@out;
}

=head2 labels( $field_id, [ include_archived => 1 ] )

The option labels, archived ones excluded unless asked for.

=cut

sub labels {
    my ( $self, $field_id, %o ) = @_;
    return map { $_->{label} } grep { $o{include_archived} || !$_->{archived} } @{ $self->options_for($field_id) };
}

sub _load {
    my $self = shift;
    return $self->_lists if $self->_lists;
    my $d = decode_json( $self->user_agent->_get('meta/lists')->{content} );
    die "unexpected /meta/lists response: expected a JSON array of list entries\n" unless ref $d eq 'ARRAY';
    $self->_lists( [ grep { ref $_ eq 'HASH' } @$d ] );
    return $self->_lists;
}

sub _entry_key { my ($e) = @_; return defined $e->{fieldId} ? "$e->{fieldId}" : defined $e->{id} ? "$e->{id}" : '' }
sub _clean { my $s = shift; $s =~ s/\s+/ /g; $s =~ s/^ | $//g; return $s }

sub _throw {
    my ( $self, $message, $code, $reason, $label ) = @_;
    my $i = 1;
    $i++ while ( ( caller($i) )[3] // '' ) =~ /::_[A-Za-z_]+$/;
    my @f = caller($i);
    WebService::BambooHR::Exception::FieldNotFound->throw({
        method => $f[3] // __PACKAGE__, message => $message, code => $code, reason => $reason,
        filename => $f[1] // '(unknown)', line_number => $f[2] // 0, label => $label,
    });
}

1;
