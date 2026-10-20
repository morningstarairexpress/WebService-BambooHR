use strict; use warnings;
use Test::More;
use JSON::MaybeXS qw( encode_json decode_json );
use FindBin qw( $Bin ); use lib "$Bin/lib";
use File::Temp qw( tempdir );
use Test::MockBambooHR;
use Test::Fixture qw( fixture fixture_text );
use WebService::BambooHR::FieldRegistry;

my $dir = tempdir( CLEANUP => 1 ); my $n = 0;
sub mock {
    Test::MockBambooHR->new
      ->stub_get( 'meta/fields', { content => fixture_text('meta-fields.json') } )
      ->stub_get( 'meta/tables', { content => fixture_text('meta-tables.json') } );
}
sub reg { my ( $m, %o ) = @_; WebService::BambooHR::FieldRegistry->new( user_agent => $m // mock(), cache_path => "$dir/" . $n++ . '.json', %o )->load }
sub err(&) { my $c = shift; eval { $c->() }; return $@ }

my $r = reg();

is( $r->resolve_field('9009'),                     '9009', 'by numeric id' );
is( $r->lookup_field('hireDate')->{id},            '3',    'by alias (standard field)' );
is( $r->lookup_field('customShirtSize')->{id},     '9001', 'by alias (custom field)' );
is( $r->lookup_field('Shirt Size')->{alias},       'customShirtSize', 'by unique display name' );
is( $r->lookup_field('shirt size')->{id},          '9001', 'display name is case-insensitive' );
is( $r->lookup_field('9100.6')->{id},              '9100.6', 'decimal sub-field id (a JSON *string* id)' );
is( $r->lookup_field('customGLCode(New)')->{id},   '9012', 'alias containing ( )' );
is( $r->lookup_field('customNotes*optional*')->{id}, '9007', 'alias containing *' );

for my $case ( [ 'Hire Date', [ 3, 9002 ] ], [ 'Job Title', [ 17, 9003 ] ], [ 'Effective Date', [ 9221, 9222 ] ], [ 'Comments', [ 9206, 9207 ] ] ) {
    my ( $label, $ids ) = @$case;
    my $e = err { $r->lookup_field($label) };
    isa_ok( $e, 'WebService::BambooHR::Exception::AmbiguousField', "'$label' is ambiguous" );
    my %got = map { $_->{id} => 1 } @{ $e->candidates };
    ok( !( grep { !$got{$_} } @$ids ), "...candidates include ids @$ids" );
    like( $e->message, qr/Use the numeric id or the alias/, '...and the message says what to do' );
}
isa_ok( err { $r->lookup_field('employmentHistoryStatus') }, 'WebService::BambooHR::Exception::AmbiguousField', 'a shared ALIAS is ambiguous too (ids 16 and "16.1")' );
isa_ok( err { $r->lookup_field('date') },                    'WebService::BambooHR::Exception::AmbiguousField', "a column alias shared by several tables" );
isa_ok( err { $r->lookup_field('No Such Field') },           'WebService::BambooHR::Exception::FieldNotFound', 'unknown key' );

{   my $f = $r->lookup_field('# of Items');
    is( $f->{id}, '9004', 'a column found by display name' );
    is( $f->{alias}, undef, '/meta/fields gives it NO alias...' );
    is_deeply( $f->{column_aliases}, ['custom#ofItems'], '...the alias exists only in /meta/tables' );
    is_deeply( $f->{keys}, [ '9004', 'custom#ofItems' ], 'keys = every name the value can arrive under (GET by id vs reports/custom)' );
    is( $r->lookup_field('custom#ofItems')->{id}, '9004', 'and that alias can be used as the lookup key' );
    my $g = $r->lookup_field('Anniversary');
    is_deeply( $g->{keys}, [ '9009', 'customAnniversary1' ], 'a field with a /meta/fields alias: id then alias' ); }

is( $r->lookup_field('Badge Number')->{id}, '9005', "a name stored with a trailing space ('Badge Number ') is found without it" );
is( $r->lookup_field('Badge Number')->{name}, 'Badge Number', '...and returned cleaned' );
is( $r->lookup_field('  badge   number ')->{id}, '9005', 'lookup keys are trimmed, collapsed and case-folded' );
is( $r->lookup_field('Parking Zone Assigned')->{id}, '9006', 'doubled internal spaces in a stored name are collapsed' );
isa_ok( err { $r->lookup_field('Plan - Employer pays') }, 'WebService::BambooHR::Exception::AmbiguousField',
        "'Plan  - Employer pays' and 'Plan - Employer pays' differ only in whitespace: ambiguous, not silently one of them" );

is( $r->resolve_table('customEquipment'), 'customEquipment', 'table by alias' );
is( $r->resolve_table('customequipment'), 'customEquipment', 'unique case-insensitive match' );
is( $r->resolve_table('customMid-MonthAdvance'), 'customMid-MonthAdvance', 'alias containing a hyphen' );
is( $r->resolve_table("customDriver'sNotes"), "customDriver'sNotes", 'alias containing an apostrophe' );
{   my $e = err { $r->resolve_table('Equipment') };
    isa_ok( $e, 'WebService::BambooHR::Exception::TableNotFound', 'a display name is not an alias' );
    like( $e->message, qr/custom tables: customDriver'sNotes, customEquipment, .*customRoleChange/, '...and the message lists the custom tables that exist' ); }
is( scalar( () = $r->table_aliases ), 8, '8 tables' );
is( scalar( () = $r->table_aliases(1) ), 6, '6 of them custom' );

is( $r->resolve_table_field( 'customEquipment', 'Item category' ), 'customItemcategory', 'by display name -> column alias (the row key)' );
is( $r->resolve_table_field( 'customEquipment', 'customSerial#' ), 'customSerial#', 'by alias, containing #' );
is( $r->resolve_table_field( 'customEquipment', '9204' ), 'customItemcost', 'by column id' );
is( $r->lookup_table_field( 'customEquipment', 'Comments' )->{id}, '9206', "'Comments' is unique inside customEquipment" );
isa_ok( err { $r->lookup_field('Comments') }, 'WebService::BambooHR::Exception::AmbiguousField', "...though it is ambiguous account-wide" );
is( $r->resolve_table_field( 'customRoleChange', 'Job Title' ), 'customJobTitle', "account-wide ambiguous 'Job Title' is unambiguous in customRoleChange" );
is( $r->resolve_table_field( 'jobInfo', 'Job Title' ), 'jobTitle', "...and in jobInfo it is a different column alias" );
is( $r->resolve_table_field( 'customLoanSchedule', 'Effective Date' ), 'customEffectiveDate3', 'collision suffixes come back from the API, never guessed' );
{   my $e = err { $r->lookup_table_field( 'customEquipment', 'Nope' ) };
    isa_ok( $e, 'WebService::BambooHR::Exception::FieldNotFound', 'unknown column' ); like( $e->message, qr/columns: 'Item category'/, '...lists the real columns' ); }
isa_ok( err { $r->lookup_table_field( 'nope', 'x' ) }, 'WebService::BambooHR::Exception::TableNotFound', 'unknown table' );

{   my @w; local $SIG{__WARN__} = sub { push @w, @_ };
    my $e = err { $r->lookup_field('Hire Date') };
    like( "$e", qr/lookup_field\(\): 'Hire Date' matches 2 fields: .* \(409 Ambiguous\) file \S+20-field-registry\.t on line \d+/, 'as_string reads sensibly' );
    is( scalar @w, 0, 'no uninitialized warnings' ) or diag @w; }

{   my $m = mock(); reg($m);
    is_deeply( [ map { $_->{path} } @{ $m->calls } ], [ 'meta/fields', 'meta/tables' ], 'only meta/fields and meta/tables are requested' ); }
{   my $m1 = mock(); my $path = "$dir/cache-roundtrip.json";
    WebService::BambooHR::FieldRegistry->new( user_agent => $m1, cache_path => $path )->load;
    my $dead = Test::MockBambooHR->new;
    my $r2 = WebService::BambooHR::FieldRegistry->new( user_agent => $dead, cache_path => $path )->load;
    is( scalar @{ $dead->calls }, 0, 'fresh cache: no API calls' );
    is_deeply( $r2->lookup_field('# of Items')->{keys}, [ '9004', 'custom#ofItems' ], 'merged aliases survive the cache round-trip' );
    is( $r2->resolve_table_field( 'customEquipment', 'Item category' ), 'customItemcategory', 'tables too' );
    my $c = decode_json( do { open my $fh, '<', $path or die; local $/; <$fh> } );
    ok( $c->{format}, 'cache records its format version' );
    is( scalar @{ $c->{fields} }, scalar @{ fixture('meta-fields.json') }, 'cache stores /meta/fields as returned (merging is redone on load)' ); }
{   my $path = "$dir/old-format.json";
    open my $fh, '>', $path or die; print {$fh} encode_json( { fields => { 1 => {} }, by_name => {}, tables => { x => {} }, loaded_at => time } ); close $fh;
    my $m = mock();
    my $r3 = WebService::BambooHR::FieldRegistry->new( user_agent => $m, cache_path => $path )->load;
    is( scalar @{ $m->calls }, 2, 'a cache written by an older format is ignored and refetched' );
    is( $r3->resolve_table('customEquipment'), 'customEquipment', '...and the registry works' ); }
{   my $m = mock();
    my $mem = WebService::BambooHR::FieldRegistry->new( user_agent => $m )->load;
    is( $mem->resolve_table('customEquipment'), 'customEquipment', 'works with no cache_path' );
    is( scalar @{ $m->calls }, 2, 'fetched once' );
    ok( !defined $mem->cache_path, 'there is no default cache location' );
    my $m2 = mock(); WebService::BambooHR::FieldRegistry->new( user_agent => $m2 )->load->load;
    is( scalar @{ $m2->calls }, 4, 'with no cache a second load() fetches again' ); }
{   my $r4 = eval { WebService::BambooHR::FieldRegistry->new( user_agent => mock(), cache_path => '/proc/no/such/dir/f.json' )->load };
    ok( $r4, 'an unwritable cache directory does not die' ); }
{   my $m = Test::MockBambooHR->new->stub_get( 'meta/fields', { content => '{"fields":[]}' } )->stub_get( 'meta/tables', { content => fixture_text('meta-tables.json') } );
    like( err { reg($m) }, qr/unexpected \/meta\/fields response/, '/meta/fields that is not an array dies loudly' );
    my $m2 = Test::MockBambooHR->new->stub_get( 'meta/fields', { content => '[]' } )->stub_get( 'meta/tables', { content => '{"tables":[]}' } );
    like( err { reg($m2) }, qr/unexpected \/meta\/tables response/, '/meta/tables that is not an array dies loudly' ); }
isa_ok( err { $r->lookup_field('Retired Field') }, 'WebService::BambooHR::Exception::DeprecatedField', 'a deprecated field (fixture)' );
{   my $m = Test::MockBambooHR->new
        ->stub_get( 'meta/fields', { content => '[{"id":1,"name":"Old","type":"text","alias":"oldField","deprecated":true},{"id":2,"name":"New","type":"text"}]' } )
        ->stub_get( 'meta/tables', { content => '[]' } );
    my $x = reg($m);
    isa_ok( err { $x->lookup_field('Old') }, 'WebService::BambooHR::Exception::DeprecatedField', 'deprecated field' );
    is( $x->resolve_field('New'), '2', 'non-deprecated resolves' ); }

# ===== one id listed more than once (a renamed field): nothing is dropped ===================================================
{   my $a = $r->lookup_field('nickname');
    my $b = $r->lookup_field('preferredName');
    is( $a->{id}, '9013', 'first listed alias resolves' );
    is( $b->{id}, '9013', 'second listed alias resolves to the same id' );
    is( $r->lookup_field('Nickname')->{id}, '9013', 'first listed display name resolves' );
    is( $r->lookup_field('preferred name')->{id}, '9013', 'second listed display name resolves, case-insensitively' );
    is( $a->{name}, 'Nickname', 'primary name is the first listed' );
    is( $a->{alias}, 'nickname', 'primary alias is the first listed' );
    is_deeply( $a->{names}, [ 'Nickname', 'Preferred Name' ], 'every name is kept' );
    is_deeply( $a->{aliases}, [ 'nickname', 'preferredName' ], 'every alias is kept' );
    is_deeply( $a->{keys}, [ '9013', 'nickname', 'preferredName' ], 'keys cover every alias, so employee_value finds the value under either' );
    is_deeply( $r->lookup_field('9013'), $a, 'lookup by id gives the same record' );
    isa_ok( err { $r->lookup_field('Work Status') }, 'WebService::BambooHR::Exception::AmbiguousField',
            'a display name shared with a DIFFERENT id is still ambiguous after merging' );
    is( $r->lookup_field('Status')->{id}, '9014', 'the other name of the renamed field resolves uniquely' );
    my $e = err { $r->lookup_field('Work Status') };
    is_deeply( [ sort map { $_->{id} } @{ $e->candidates } ], [ 9014, 9015 ], 'the ambiguity lists each id once, not once per entry' );
    my $m = mock(); my $x = reg($m);
    my $dead = Test::MockBambooHR->new; my $path = "$dir/dupid.json";
    WebService::BambooHR::FieldRegistry->new( user_agent => $m, cache_path => $path )->load;
    my $c = WebService::BambooHR::FieldRegistry->new( user_agent => $dead, cache_path => $path )->load;
    is( $c->lookup_field('nickname')->{id}, '9013', 'a duplicate-id entry survives the cache round-trip' );
    is( scalar @{ $dead->calls }, 0, '...without refetching' ); }

# a field is deprecated only if EVERY entry for its id is
{   my $m = Test::MockBambooHR->new
        ->stub_get( 'meta/fields', { content => '[{"id":5,"name":"Old","type":"text","alias":"oldA","deprecated":true},{"id":5,"name":"Older","type":"text","alias":"oldB","deprecated":true},{"id":6,"name":"Half","type":"text","alias":"halfA","deprecated":true},{"id":6,"name":"Half Live","type":"text","alias":"halfB"}]' } )
        ->stub_get( 'meta/tables', { content => '[]' } );
    my $x = reg($m);
    isa_ok( err { $x->lookup_field('oldB') }, 'WebService::BambooHR::Exception::DeprecatedField', 'all entries deprecated: deprecated' );
    is( $x->lookup_field('halfA')->{id}, '6', 'only one of two entries deprecated: still usable' ); }
done_testing;
