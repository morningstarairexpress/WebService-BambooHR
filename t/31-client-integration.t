use strict; use warnings;
use Test::More;
use FindBin qw( $Bin ); use lib "$Bin/lib";
use File::Temp qw( tempdir );
use Test::Fixture qw( fixture_text fixture );

# Drives the REAL (patched) WebService::BambooHR client with response shapes the API was observed to return.
use WebService::BambooHR;
plan skip_all => 'WebService::BambooHR does not have the custom-fields support (_post_json)' unless WebService::BambooHR->can('_post_json');
use WebService::BambooHR::FieldRegistry;
use WebService::BambooHR::TabularData;
use WebService::BambooHR::ListOptions;
use WebService::BambooHR::MappingValidator qw( validate_mapping request_fields employee_value );

{   package FakeUA;
    sub new { bless { seen => [], routes => [] }, shift }
    sub route { my ($s,$m,$re,$r)=@_; push @{$s->{routes}}, [$m,$re,$r]; $s }
    sub request {
        my ($s,$m,$url,$o)=@_; push @{$s->{seen}}, { method=>$m, url=>$url, %$o };
        for my $r (reverse @{$s->{routes}}) { return { success=>1, status=>200, reason=>'OK', headers=>{}, %{$r->[2]} } if $m eq $r->[0] && $url =~ $r->[1] }
        return { success=>0, status=>404, reason=>'Not Found', headers=>{}, content=>'' };
    }
}
my $ua = FakeUA->new
  ->route( GET  => qr{/meta/fields$},                         { content => fixture_text('meta-fields.json') } )
  ->route( GET  => qr{/meta/tables$},                         { content => fixture_text('meta-tables.json') } )
  ->route( GET  => qr{/meta/lists$},                          { content => fixture_text('meta-lists.json') } )
  ->route( GET  => qr{/employees/111\?fields=},               { content => fixture_text('employee-by-id.json') } )
  ->route( POST => qr{/reports/custom},                       { content => fixture_text('report-custom.json') } )
  ->route( GET  => qr{/employees/all/tables/customEquipment$},{ content => fixture_text('rows-all-customEquipment.json') } )
  ->route( GET  => qr{/employees/111/tables/customEquipment$},{ content => fixture_text('rows-customEquipment.json') } );
sub client { WebService::BambooHR->new( company => 'acme', api_key => 'KEY', ua => $ua, @_ ) }

my $dir = tempdir( CLEANUP => 1 );
my $reg = WebService::BambooHR::FieldRegistry->new( user_agent => client(), cache_path => "$dir/f.json" )->load;
is_deeply( [ map { $_->{url} } @{ $ua->{seen} } ],
           [ 'https://api.bamboohr.com/api/gateway.php/acme/v1/meta/fields', 'https://api.bamboohr.com/api/gateway.php/acme/v1/meta/tables' ],
           'registry used the client transport: only meta/fields and meta/tables' );

my $res = validate_mapping( $reg, {
    employee_fields => { items => '# of Items', shirt => 'Shirt Size', anniv => 'Anniversary' },
    tables          => { equipment => { table_alias => 'customEquipment', columns => { category => 'Item category' } } },
} );
is_deeply( request_fields( $res->{employee} ), { items => '9004', shirt => '9001', anniv => '9009' }, 'request_fields' );

my $cl = client( custom_fields => request_fields( $res->{employee} ) );
my $e  = $cl->employee( 111, 'firstName', 'items', 'shirt', 'anniv' );
like( $ua->{seen}[-1]{url}, qr{/employees/111\?fields=firstName,9004,9001,9009$}, 'GET employee requests numeric ids (an alias like custom#ofItems would break the query string)' );
is( $e->custom('items'), '3', 'GET employee: returned under the id, found by logical name' );
is( employee_value( $e, $res->{employee}{items} ), '3', 'GET employee: employee_value' );

my ($l) = $cl->employee_list( 'firstName', 'items', 'shirt', 'anniv' );
like( $ua->{seen}[-1]{content}, qr{<field id="9004" />\s*<field id="9001" />\s*<field id="9009" />}s, 'report asks for numeric ids' );
is( $l->custom('items'), undef, 'documents the pitfall: custom(logical name) misses a reports/custom value, because that call keys it by alias' );
is( $l->custom('custom#ofItems'), '3', '...it is there under the alias' );
for my $name (qw( items shirt anniv )) {
    ok( defined employee_value( $l, $res->{employee}{$name} ), "employee_list: employee_value finds $name whichever key was used" );
}
is( employee_value( $l, $res->{employee}{anniv} ), '2020-02-02', 'a field that has a /meta/fields alias (customAnniversary1) as well' );

my $td = WebService::BambooHR::TabularData->new( user_agent => $cl );
my ($row) = $td->get_rows( 111, $res->{tables}{equipment}{alias} );
is( $row->field( $res->{tables}{equipment}{columns}{category} ), 'Laptop', 'row value via the resolved column record' );
is_deeply( [ sort { $a <=> $b } keys %{ $td->rows_by_employee('customEquipment') } ], [ 1, 3 ], 'employees/all/tables through the client' );
my $lists = WebService::BambooHR::ListOptions->new( user_agent => $cl );
is_deeply( [ $lists->labels( $res->{tables}{equipment}{columns}{category}{id} ) ], [ 'Laptop', 'Phone', 'Badge' ], 'list options through the client' );

my $plain = client();
ok( !eval { $plain->_check_fields('items'); 1 }, 'a client without custom_fields rejects the logical name' );
done_testing;
