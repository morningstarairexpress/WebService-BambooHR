use strict; use warnings;
use Test::More;
use JSON::MaybeXS qw( encode_json );
use FindBin qw( $Bin ); use lib "$Bin/lib";
use Test::MockBambooHR;
use Test::Fixture qw( fixture_text fixture );
use WebService::BambooHR::TabularData;

sub td { my $m = Test::MockBambooHR->new; return ( WebService::BambooHR::TabularData->new( user_agent => $m ), $m ) }

{   my ( $t, $m ) = td();
    $m->stub_get( 'employees/111/tables/customEquipment', { content => fixture_text('rows-customEquipment.json') } );
    my @rows = $t->get_rows( 111, 'customEquipment' );
    is( scalar @rows, 7, 'seven rows' );
    my $r = $rows[0];
    is( $r->row_id, '812', 'numeric row id stored as a string' );
    is( $r->employee_id, '111', 'numeric employeeId stored as a string' );
    ok( !exists $r->fields->{id} && !exists $r->fields->{employeeId}, 'id/employeeId lifted out of fields' );
    ok( exists $r->fields->{'customSerial#'}, 'column alias containing # is kept verbatim' );
    is( $r->field('customItemcategory'), 'Laptop', 'field() by column alias' );
    is( $r->field( { id => 9201, alias => 'customItemcategory' } ), 'Laptop', 'field() by resolved column record' );
    is( $r->field('9201'), undef, 'rows are NOT keyed by column id' ); }
{   my ( $t, $m ) = td();
    $m->stub_get( 'employees/111/tables/jobInfo', { content => fixture_text('rows-jobInfo.json') } );
    my ( $r ) = $t->get_rows( 111, 'jobInfo' );
    is( $r->row_id, '379', 'string row id' );
    is( $r->employee_id, '111', 'string employee id' );
    is( $r->field('jobTitle'), 'Analyst', 'value by alias' ); }
{   my ( $t, $m ) = td();
    $m->stub_get( 'employees/all/tables/a', { content => '[{"id":"379","employeeId":"111","x":"1"},{"id":812,"employeeId":111,"x":"2"}]' } );
    my @r = $t->all_rows('a');
    is_deeply( [ map { $_->row_id } @r ], [ '379', '812' ], 'row ids: JSON string and number -> same string form' );
    is_deeply( [ map { $_->employee_id } @r ], [ '111', '111' ], 'employeeId: JSON string and number -> same string form' );
    $m->stub_get( 'employees/all/tables/b', { content => '[{"id":1,"employeeId":111},{"id":2,"employeeId":"111"}]' } );
    is( scalar @{ $t->rows_by_employee('b')->{111} }, 2, 'grouping key is identical whichever JSON type BambooHR used' ); }
{   my ( $t, $m ) = td();
    $m->stub_get( 'employees/111/tables/customMid-MonthAdvance', { content => fixture_text('rows-empty.json') } );
    is( scalar( () = $t->get_rows( 111, 'customMid-MonthAdvance' ) ), 0, 'an employee with no rows gets []' ); }
{   my ( $t, $m ) = td();
    $m->stub_get( 'employees/all/tables/customEquipment', { content => fixture_text('rows-all-customEquipment.json') } );
    my $by = $t->rows_by_employee('customEquipment');
    is( scalar @{ $m->calls }, 1, 'a single request' );
    is( $m->calls->[0]{path}, 'employees/all/tables/customEquipment', 'employees/all/tables/{table}' );
    is_deeply( [ sort { $a <=> $b } keys %$by ], [ 1, 3 ], 'grouped by employee id (strings)' );
    is( scalar @{ $by->{1} }, 2, 'employee 1 has two rows' );
    is( scalar @{ $by->{3} }, 4, 'employee 3 has four rows' ); }
{   my ( $t, $m ) = td();
    $m->stub_get( qr{^employees/changed/tables/customEquipment\?since=}, { content => fixture_text('changed-tables-customEquipment.json') } );
    my $c = $t->changed_rows( 'customEquipment', '2026-09-02T22:56:10Z' );
    like( $m->calls->[0]{path}, qr/since=2026-09-02T22%3A56%3A10Z$/, 'since is percent-encoded' );
    is_deeply( [ sort { $a <=> $b } keys %$c ], [ 1, 102, 104, 106 ], 'four employees' );
    is( $c->{1}{last_changed}, '2026-09-30T07:04:13+00:00', 'lastChanged carried through' );
    is( scalar @{ $c->{1}{rows} }, 2, 'rows come from the nested rows array' );
    is( scalar @{ $c->{104}{rows} }, 3, '...for each employee' );
    is( $c->{1}{rows}[0]->employee_id, '1', 'employee id taken from the map key' );
    is( $c->{1}{rows}[0]->row_id, undef, 'changed rows carry no row id' );
    ok( exists $c->{1}{rows}[0]->fields->{customItemcategory}, 'columns by alias' ); }
for my $body ( '{"employees":[],"table":"x"}', '{"employees":{},"table":"x"}', '{"table":"x"}' ) {
    my ( $t, $m ) = td(); $m->stub_get( qr{^employees/changed/tables/x}, { content => $body } );
    is_deeply( $t->changed_rows( 'x', '2026-01-01T00:00:00Z' ), {}, "no changes: $body" );
}
{   my ( $t, $m ) = td();
    $m->stub_get( qr{employees/1/tables/}, { content => '{"rows":[]}' } );
    eval { $t->get_rows( 1, 'x' ) }; isa_ok( $@, 'WebService::BambooHR::Exception', 'rows that are not an array' ); is( $@->code, 502, '...502' );
    $m->stub_get( qr{^employees/changed/tables/y}, { content => '{"employees":{"7":["a"]}}' } );
    eval { $t->changed_rows( 'y', 'z' ) }; isa_ok( $@, 'WebService::BambooHR::Exception', 'changed entry that is not {lastChanged, rows}' );
    $m->stub_get( qr{^employees/changed/tables/w}, { content => '{"employees":[1,2]}' } );
    eval { $t->changed_rows( 'w', 'z' ) }; isa_ok( $@, 'WebService::BambooHR::Exception', 'non-empty array of employees' ); }
{   my ( $t, $m ) = td();
    $m->stub_get( qr{^employees/}, { content => '[]' } );
    $t->get_rows( 111, "customDriver'sNotes" ); $t->get_rows( 111, 'customMid-MonthAdvance' );
    is( $m->calls->[0]{path}, 'employees/111/tables/customDriver%27sNotes', "apostrophe -> %27" );
    is( $m->calls->[1]{path}, 'employees/111/tables/customMid-MonthAdvance', 'hyphen is left alone' ); }
{   my ( $t, $m ) = td();
    $m->stub_post( 'employees/123/tables/customEquipment', { headers => { location => '/v1/employees/123/tables/customEquipment/42' } } );
    is( $t->add_row( 123, 'customEquipment', { customItemcategory => 'Badge' } ), '42', 'new row id from Location' );
    like( $m->calls->[0]{body}, qr/"customItemcategory":"Badge"/, 'JSON body' );
    my $m2 = Test::MockBambooHR->new->stub_post( 'employees/123/tables/customEquipment', { headers => {} } );
    eval { WebService::BambooHR::TabularData->new( user_agent => $m2 )->add_row( 123, 'customEquipment', {} ) };
    ok( $@, 'add_row dies without a Location header' );
    $m->stub_delete( 'employees/123/tables/customEquipment/9', { success => 1 } );
    ok( $t->delete_row( 123, 'customEquipment', 9 ), 'delete_row' ); }
{   my $r = WebService::BambooHR::TableRow->new( employee_id => 1, fields => { a => '', b => undef, c => 'x' } );
    is_deeply( $r->normalized_fields, { a => undef, b => undef, c => 'x' }, '"" and null both normalise to undef' ); }
done_testing;
