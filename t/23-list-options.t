use strict; use warnings;
use Test::More;
use JSON::MaybeXS qw( encode_json );
use FindBin qw( $Bin ); use lib "$Bin/lib";
use Test::MockBambooHR;
use Test::Fixture qw( fixture_text fixture );
use WebService::BambooHR::ListOptions;

# t/data/meta-lists.json has the observed key names; the values of "archived" were never captured (see t/data/README.md).
sub lists { my ($body) = @_; my $m = Test::MockBambooHR->new->stub_get( 'meta/lists', { content => $body // fixture_text('meta-lists.json') } );
            return ( WebService::BambooHR::ListOptions->new( user_agent => $m ), $m ) }
sub err(&) { my $c = shift; eval { $c->() }; return $@ }

{   my ( $l, $m ) = lists();
    is_deeply( [ $l->labels(9215) ], [ 'Female', 'Male' ], 'labels in the order BambooHR gave them; the archived option is left out' );
    is_deeply( [ $l->labels( 9215, include_archived => 1 ) ], [ 'Female', 'Male', 'Unspecified' ], '...and included on request' );
    is_deeply( [ $l->labels('9216') ], [ 'Child', 'Parent', 'Friend', 'Partner' ], 'a trailing space in a label is trimmed' );
    is_deeply( [ $l->labels(18) ], [], 'a list with no options is an empty list, not an error' );
    is_deeply( [ map { $_->{path} } @{ $m->calls } ], ['meta/lists'], 'one request, however many lookups' );
    is( $l->options_for(9215)->[0]{archived}, 0, 'archived flag present' );
    is( $l->options_for(9215)->[2]{archived}, 1, '...and set for the archived option' ); }
{   my ( $l ) = lists( encode_json([ { fieldId => 9, id => 9, name => 'X', options => [ { name => 'A', archived => 'no' }, { name => 'B', archived => 'yes' }, { name => 'C', archived => 'true' }, { name => 'D' } ] } ]) );
    is_deeply( [ $l->labels(9) ], [ 'A', 'D' ], 'archived options (yes/true) are excluded by default' );
    is_deeply( [ $l->labels( 9, include_archived => 1 ) ], [ 'A', 'B', 'C', 'D' ], '...and included on request' ); }
{   my ( $l ) = lists( encode_json([ { fieldId => 5, id => 100, options => [ 'plain', { value => 'viaValue' }, { name => '  spaced   out ' } ] } ]) );
    is_deeply( [ $l->labels(5) ], [ 'plain', 'viaValue', 'spaced out' ], 'bare strings, a "value" key, and whitespace collapsing are all accepted' ); }
{   my ( $l ) = lists( encode_json([
        { fieldId => 7,    id => 9215, options => [ { name => 'decoy' } ] },
        { fieldId => 9215, id => 1,    options => [ { name => 'right' } ] },
        { id => 55, options => [ { name => 'by-id-only' } ] },
    ]) );
    is_deeply( [ $l->labels(9215) ], ['right'], "fieldId wins over another list's id" );
    is_deeply( [ $l->labels(55) ], ['by-id-only'], 'id is used when an entry has no fieldId' ); }
{   my ( $l ) = lists();
    my $e = err { $l->options_for(99999) };
    isa_ok( $e, 'WebService::BambooHR::Exception::FieldNotFound', 'no list for the field' );
    like( $e->message, qr/no BambooHR list has fieldId '99999'/, '...says which' );
    like( "$e", qr/options_for\(\): .* \(404 Not Found\) file \S+23-list-options\.t on line \d+/, 'stringifies via the base exception' ); }
{   my ( $l ) = lists( encode_json([ { fieldId => 1, options => [] }, { fieldId => 1, options => [] } ]) );
    like( err { $l->options_for(1) }->message, qr/more than one BambooHR list claims fieldId '1'/, 'two lists for one field: ambiguous, not a guess' ); }
{   my ( $l ) = lists( encode_json([ { fieldId => 1 } ]) );
    like( err { $l->options_for(1) }->message, qr/no 'options' array \(keys seen: fieldId\)/, 'an entry without options says which keys it had' );
    my ( $l2 ) = lists( encode_json([ { fieldId => 1, options => [ { id => 3, label => 'x' } ] } ]) );
    like( err { $l2->options_for(1) }->message, qr/no usable label \(keys seen: id,label\)/, 'an option shape this reader does not know says which keys it had' );
    my ( $l3 ) = lists( encode_json({ lists => [] }) );
    like( err { $l3->options_for(1) }, qr/unexpected \/meta\/lists response/, 'a non-array response dies loudly' ); }
done_testing;
