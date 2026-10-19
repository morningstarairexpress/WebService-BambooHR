package Test::MockBambooHR;
use 5.010; use strict; use warnings; use Moo; use JSON::MaybeXS ();

# Duck-typed stand-in for the WebService::BambooHR client (_get/_post/_post_json/_delete).
# An un-stubbed call dies, so a missing stub can never silently pass a test.
has '_stubs' => ( is => 'ro', default => sub { { GET => [], POST => [], DELETE => [] } } );
has 'calls'  => ( is => 'ro', default => sub { [] } );

sub stub_get    { push @{ $_[0]->_stubs->{GET} },    [ $_[1], $_[2] ]; $_[0] }
sub stub_post   { push @{ $_[0]->_stubs->{POST} },   [ $_[1], $_[2] ]; $_[0] }
sub stub_delete { push @{ $_[0]->_stubs->{DELETE} }, [ $_[1], $_[2] ]; $_[0] }

sub _get    { my ( $s, $p ) = @_; push @{ $s->calls }, { method => 'GET',    path => $p }; $s->_hit( GET    => $p ) }
sub _delete { my ( $s, $p ) = @_; push @{ $s->calls }, { method => 'DELETE', path => $p }; $s->_hit( DELETE => $p ) }
sub _post   { my ( $s, $p, $b ) = @_; push @{ $s->calls }, { method => 'POST', path => $p, body => $b }; $s->_hit( POST => $p ) }
sub _post_json {
    my ( $s, $p, $d ) = @_;
    my $b = ref $d ? JSON::MaybeXS::encode_json($d) : $d;
    push @{ $s->calls }, { method => 'POST', path => $p, body => $b, json => 1 };
    return $s->_hit( POST => $p );
}
sub _hit {
    my ( $s, $verb, $path ) = @_;
    for my $st ( reverse @{ $s->_stubs->{$verb} } ) {
        my ( $pat, $resp ) = @$st;
        return $resp if ref $pat eq 'Regexp' ? $path =~ $pat : $path eq $pat;
    }
    die "Test::MockBambooHR: no stub for $verb '$path'\n";
}
1;
