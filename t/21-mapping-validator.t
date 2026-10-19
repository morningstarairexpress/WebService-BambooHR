use strict; use warnings;
use Test::More;
use FindBin qw( $Bin ); use lib "$Bin/lib";
use File::Temp qw( tempdir );
use Test::MockBambooHR;
use Test::Fixture qw( fixture fixture_text );
use WebService::BambooHR::FieldRegistry;
use WebService::BambooHR::MappingValidator qw( validate_mapping request_fields employee_value );

my $dir = tempdir( CLEANUP => 1 ); my $n = 0;
sub registry {
    my $m = Test::MockBambooHR->new
      ->stub_get( 'meta/fields', { content => fixture_text('meta-fields.json') } )
      ->stub_get( 'meta/tables', { content => fixture_text('meta-tables.json') } );
    WebService::BambooHR::FieldRegistry->new( user_agent => $m, cache_path => "$dir/" . $n++ . '.json' )->load;
}
sub err(&) { my $c = shift; eval { $c->() }; return $@ }

my $ok = {
    employee_fields => { hired => 'hireDate', shirt => 'Shirt Size', items => '# of Items', anniv => 9009 },
    tables => {
        equipment => { table_alias => 'customEquipment', columns => { category => 'Item category', serial => 'customSerial#', cost => 9204, comments => 'Comments' } },
        guests    => { table_alias => 'customGuests',    columns => { first => 'Guest First Name', relationship => 'Guest Relationship' } },
    },
};
my $res = validate_mapping( registry(), $ok );

is( $res->{employee}{hired}{id}, '3', 'alias -> id' );
is( $res->{employee}{shirt}{alias}, 'customShirtSize', 'display name -> record with alias' );
is_deeply( $res->{employee}{items}{keys}, [ '9004', 'custom#ofItems' ], 'record lists every key the value can arrive under' );
is( $res->{employee}{anniv}{name}, 'Anniversary', 'numeric id accepted' );
is_deeply( [ sort keys %{ $res->{tables} } ], [ 'equipment', 'guests' ], "several tables resolved independently, under the caller's own names" );
is( $res->{tables}{equipment}{alias}, 'customEquipment', 'table alias' );
is( $res->{tables}{equipment}{columns}{category}{alias}, 'customItemcategory', 'column -> row key' );
is( $res->{tables}{equipment}{columns}{serial}{alias}, 'customSerial#', 'alias with # accepted' );
is( $res->{tables}{equipment}{columns}{cost}{id}, '9204', 'column by id' );
is( $res->{tables}{equipment}{columns}{comments}{id}, '9206', "'Comments' is resolved inside the table, where it is unambiguous" );
is( $res->{tables}{guests}{columns}{relationship}{id}, '9216', 'the second table' );
is_deeply( request_fields( $res->{employee} ), { hired => '3', shirt => '9001', items => '9004', anniv => '9009' }, 'request_fields: logical name => numeric id' );

{   package StubEmployee;
    sub new { my ( $c, %h ) = @_; bless { extra => {%h} }, $c }
    sub custom { $_[0]{extra}{ $_[1] } }
}
my $items  = $res->{employee}{items};
my $by_id  = StubEmployee->new( %{ fixture('employee-by-id.json') } );
my $report = StubEmployee->new( %{ fixture('report-custom.json')->{employees}[0] } );
ok( exists $by_id->{extra}{9004} && !exists $by_id->{extra}{'custom#ofItems'}, 'fixture: GET by id keys the value by id' );
ok( exists $report->{extra}{'custom#ofItems'} && !exists $report->{extra}{9004}, 'fixture: reports/custom keys the SAME field by alias' );
is( employee_value( $by_id,  $items ), '3', 'employee_value finds it from a GET-by-id result' );
is( employee_value( $report, $items ), '3', 'employee_value finds it from a reports/custom result' );
is( employee_value( StubEmployee->new, $items ), undef, 'undef when absent' );
is( $report->custom( $items->{id} ), undef, 'looking up only by id misses the reports/custom value' );

{   my $e = err { validate_mapping( registry(), {
        employee_fields => { good => 'Shirt Size', ambiguous => 'Hire Date', missing => 'No Such Thing' },
        tables          => { t => { table_alias => 'customEquipment', columns => { good => 'Item category', bad => 'Nope' } } },
    } ) };
    like( $e, qr/\(3 errors\)/, 'three errors aggregated' );
    like( $e, qr/employee_fields\.ambiguous \('Hire Date'\): .*matches 2 fields: id 3 .*id 9002/, 'ambiguity names both ids' );
    like( $e, qr/employee_fields\.missing/, 'missing field named' );
    like( $e, qr/tables\.t\.columns\.bad .*no column matching 'Nope'/s, 'bad column named, with its logical path' );
    unlike( $e, qr/employee_fields\.good|columns\.good/, 'good entries not reported' ); }
{   my $e = err { validate_mapping( registry(), { tables => { t => { table_alias => 'Equipment List', columns => { a => 'x', b => 'y' } } } } ) };
    like( $e, qr/\(1 error\)/, 'a bad table yields one error, not one per column' );
    like( $e, qr/tables\.t\.table_alias .*not display name; custom tables: customDriver'sNotes, customEquipment/, 'and says tables are identified by alias' );
    like( err { validate_mapping( registry(), { tables => { t => {} } } ) }, qr/tables\.t\.table_alias: not set/, 'missing table_alias reported' );
    like( err { validate_mapping( registry(), { tables => { a => { table_alias => 'nope1' }, b => { table_alias => 'nope2' } } } ) }, qr/\(2 errors\)/, 'every bad table is reported' ); }
{   my $e = validate_mapping( registry(), {} );
    is_deeply( $e, { employee => {}, tables => {} }, 'nothing configured: empty employee and tables, both present' );
    is_deeply( request_fields( $e->{employee} ), {}, 'request_fields of nothing is {}' ); }
done_testing;
