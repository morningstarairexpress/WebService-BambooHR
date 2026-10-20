use strict; use warnings;
use Test::More;
use MIME::Base64 qw( encode_base64 );
use JSON::MaybeXS qw( encode_json );
use FindBin qw( $Bin ); use lib "$Bin/lib";

# Runs against the REAL upstream classes after patches/0001-custom-fields.patch.
use WebService::BambooHR;
plan skip_all => 'patches/0001-custom-fields.patch not applied' unless WebService::BambooHR->can('_post_json');

{   package FakeUA;     # canned HTTP layer standing in for HTTP::Tiny
    sub new { bless { seen => [], routes => [] }, shift }
    sub route { my ($s,$m,$re,$r)=@_; push @{$s->{routes}}, [$m,$re,$r]; $s }
    sub request {
        my ($s,$m,$url,$o)=@_; push @{$s->{seen}}, { method=>$m, url=>$url, %$o };
        for my $r (reverse @{$s->{routes}}) { return { success=>1, status=>200, reason=>'OK', headers=>{}, %{$r->[2]} } if $m eq $r->[0] && $url =~ $r->[1] }
        return { success=>0, status=>404, reason=>'Not Found', headers=>{}, content=>'' };
    }
}
my $base = 'https://api.bamboohr.com/api/gateway.php/acme/v1/';
sub client { my %o=@_; my $ua=FakeUA->new; (WebService::BambooHR->new( company=>'acme', api_key=>'KEY', ua=>$ua, %o ), $ua) }
sub via_method { $_[0]->_get('meta/fields') }     # upstream's _get reads caller(1): call it from inside a sub, as real methods do

# --- transport ---------------------------------------------------------------------------------
{   my ($b,$ua) = client();
    $ua->route( GET => qr{/meta/fields$}, { content => '[]' } )
       ->route( DELETE => qr{/employees/1/tables/t/9$}, {} )->route( POST => qr{/employees/1/tables/t$}, {} );
    via_method($b);
    is( $ua->{seen}[0]{url}, $base.'meta/fields', 'URL built as upstream builds it' );
    is( $ua->{seen}[0]{headers}{Authorization}, 'Basic '.encode_base64('KEY:x',''), 'Basic auth, key as user' );
    $b->_delete('employees/1/tables/t/9');
    is( $ua->{seen}[1]{method}, 'DELETE', '_delete uses DELETE' );
    $b->_post_json( 'employees/1/tables/t', { a => 1 } );
    is( $ua->{seen}[2]{headers}{'Content-Type'}, 'application/json', '_post_json sets Content-Type' );
    is( $ua->{seen}[2]{content}, '{"a":1}', 'JSON body' );
    my @w; local $SIG{__WARN__} = sub { push @w, @_ };
    eval { $b->_delete('nope') };
    isa_ok( $@, 'WebService::BambooHR::Exception' ); is( $@->code, 404, 'failure -> upstream Exception with HTTP code' );
    is( scalar @w, 0, 'no warnings' ); }

# --- custom_fields: per instance, order independent, three accepted forms -----------------------------
{   my ($a) = client( custom_fields => { shirt_size => '9001' } );
    my ($b) = client( custom_fields => { other => '9999' } );
    is_deeply( [ $a->_check_fields( 'shirt_size', 'firstName', '9001', 'selfServiceAccess' ) ],
               [ '9001', 'firstName', '9001', '1610' ], 'logical name | standard | configured id | upstream alias' );
    eval { $a->_check_fields('superheroName') };
    like( "$@", qr/unknown field name 'superheroName'/, 'unknown field still rejected' ); is( $@->code, 400, '...with 400' );
    eval { $b->_check_fields('shirt_size') }; ok( $@, "client B does not see client A's mapping" );
    ok(  ( grep { $_ eq '9001' } $a->_field_list ), '_field_list includes the configured id' );
    ok( !( grep { $_ eq '9001' } $b->_field_list ), '...only for the instance that configured it' );
    ok( !( grep { $_ eq '9001' } (client())[0]->_field_list ), 'a client created later is unaffected' );
    my ($fresh) = client( custom_fields => { shirt_size => '9001' } );
    ok( eval { $fresh->_check_fields('shirt_size'); 1 }, 'explicit custom field accepted without a prior _field_list() (PR #5 regression)' );
    my ($pr) = client( custom_fields => ['customShirtSize'] );
    is_deeply( { %{ $pr->custom_fields } }, { customShirtSize => 'customShirtSize' }, 'arrayref coerced to name=>name' );
    ok( eval { $pr->_check_fields('customShirtSize'); 1 }, 'PR #5 style name accepted' ); }

# --- Employee: custom values -------------------------------------------------------------------
{   my ($b,$ua) = client( custom_fields => { shirt_size => '9001', anniversary => '9002', firstname => 'firstName' } );
    $ua->route( GET => qr{/employees/7\?fields=}, { content =>
        '{"id":"7","firstName":"Ada","lastName":"Lovelace","9001":"M","9002.0":"2020-02-02","1610":"Yes"}' } );
    my $e = $b->employee(7);
    like( $ua->{seen}[0]{url}, qr/fields=.*\b9001\b/, 'default request includes the custom ids' );
    is( $e->firstName, 'Ada', 'standard accessor unchanged' );
    is( $e->selfServiceAccess, 'Yes', "upstream init_arg (1610) unchanged" );
    is( $e->custom('shirt_size'), 'M', 'custom() by logical name' );
    is( $e->custom('anniversary'), '2020-02-02', "'9002.0' normalised to '9002'" );
    is( $e->custom(9001), 'M', 'custom() by raw id' );
    is( $e->custom('firstname'), 'Ada', 'logical name mapped onto a standard field' );
    is_deeply( [ sort keys %{ $e->extra } ], [ '9001', '9002' ], 'only custom ids land in the bag' );
    is( "$e", 'Ada Lovelace', 'string overload still works' );

    $ua->route( POST => qr{/reports/custom}, { content => '{"employees":[{"id":"7","firstName":"Ada","lastName":"L","9001":"M"}]}' } );
    my ($le) = $b->employee_list( 'firstName', 'shirt_size' );
    like( $ua->{seen}[-1]{content}, qr/<field id="9001" \/>/, 'report requests the resolved id' );
    is( $le->custom('shirt_size'), 'M', 'employee_list populates custom fields' );

    $ua->route( GET => qr{/employees/directory$}, { content => '{"employees":[{"id":"7","displayName":"Ada","firstName":"Ada","lastName":"L","9001":"M"}]}' } );
    my ($de) = $b->employee_directory;
    is( $de->custom('shirt_size'), 'M', 'employee_directory populates custom fields' ); }

# --- values that broke PR #5's generated accessors ---------------------------------------------------------
{   for my $case ( [ 'alias with no custom prefix', 'shirtSize' ], [ "alias containing a quote", "customIt's" ] ) {
        my ( $label, $key ) = @$case;
        my ($b,$ua) = client( custom_fields => { x => $key } );
        $ua->route( GET => qr{/employees/7\?fields=}, { content => encode_json({ id=>7, firstName=>'A', lastName=>'B', $key => 'v' }) } );
        is( $b->employee( 7, 'firstName', 'x' )->custom('x'), 'v', "$label: value reachable" ); }
    ok( !WebService::BambooHR::Employee->can('customShirtSize'), 'no methods are generated on the class' );
    my $e = WebService::BambooHR::Employee->new( firstName => 'A', lastName => 'B', 9001 => 'M' );
    eval { $e->custom( 9001, 'XL' ) };
    is( $e->custom(9001), 'M', 'custom() is read-only' ); }

# --- write path: logical names are sent as ids (and upstream's stale-variable bug is gone) ----------------------
{   my ($b) = client( custom_fields => { shirt_size => '9001' } );
    my @w; local $SIG{__WARN__} = sub { push @w, @_ };
    my $xml = $b->_employee_record({ firstName => 'Ada', lastName => 'Lovelace', shirt_size => 'M', selfServiceAccess => 'Yes' });
    like( $xml, qr/<field id="firstName">Ada<\/field>/,     'plain field keeps its own id (upstream wrote it under a stale/empty id)' );
    like( $xml, qr/<field id="lastName">Lovelace<\/field>/, 'second plain field too' );
    like( $xml, qr/<field id="9001">M<\/field>/,          'logical custom name -> id' );
    like( $xml, qr/<field id="1610">Yes<\/field>/,          'upstream alias still mapped' );
    unlike( $xml, qr/id=""/, 'no empty field ids' ); is( scalar @w, 0, 'no warnings' ); }

# --- a logical name that is the same string as the alias BambooHR returns the value under -------------------------------------
{   my ($b,$ua) = client( custom_fields => { hiredOn => '9050', otherName => '9051' } );
    $ua->route( GET => qr{/employees/7\?fields=}, { content => '{"id":"7","firstName":"A","lastName":"B","hiredOn":"2012-05-05","9051":"x"}' } );
    my $e = $b->employee( 7, 'firstName', 'hiredOn', 'otherName' );
    is( $e->custom('hiredOn'), '2012-05-05', 'logical name equal to the alias: the value stored under the alias is found' );
    is( $e->custom('otherName'), 'x', 'a logical name that differs from the alias still resolves through its id' );
    is( $e->custom('nothing'), undef, 'an unknown key is undef' ); }
done_testing;
