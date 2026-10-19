use strict; use warnings;
use Test::More;
use JSON::MaybeXS qw( encode_json );
use FindBin qw( $Bin ); use lib "$Bin/lib";
use File::Temp qw( tempdir );
use Test::MockBambooHR;
use Test::Fixture qw( fixture fixture_text );
use WebService::BambooHR::FieldRegistry;
use WebService::BambooHR::MappingValidator qw( validate_mapping );

# A six-column table whose display names carry stray whitespace and repeat names used elsewhere in the account.
my $dir = tempdir( CLEANUP => 1 ); my $n = 0;
sub registry {
    my $m = Test::MockBambooHR->new
      ->stub_get( 'meta/fields', { content => fixture_text('meta-fields.json') } )
      ->stub_get( 'meta/tables', { content => fixture_text('meta-tables.json') } );
    WebService::BambooHR::FieldRegistry->new( user_agent => $m, cache_path => "$dir/" . $n++ . '.json', @_ )->load;
}
sub err(&) { my $c = shift; eval { $c->() }; return $@ }
my $r = registry();

my %want = ( 'Guest First Name' => 'customGuestFirstName', 'Guest Middle Name' => 'customGuestMiddleName', 'Guest Last Name' => 'customGuestLastName',
             'Guest Birthdate' => 'customGuestBirthdate', 'Guest Gender' => 'customGuestGender', 'Guest Relationship' => 'customGuestRelationship' );
is( $r->resolve_table_field( 'customGuests', $_ ), $want{$_}, "'$_' -> $want{$_}" ) for sort keys %want;
is( $r->lookup_table_field( 'customGuests', 'Guest Middle Name' )->{name}, 'Guest Middle Name', 'the stored name (with a trailing space) is returned cleaned' );
for my $k ( 'Guest Middle Name ', '  guest   middle   name', "GUEST\tMIDDLE NAME" ) {
    is( $r->resolve_table_field( 'customGuests', $k ), 'customGuestMiddleName', 'key ' . ( $k =~ s/\t/\\t/gr ) . ' matches' );
}
is( $r->resolve_table_field( 'customGuests', '9214' ), 'customGuestBirthdate', 'by column id' );
is( $r->resolve_table_field( 'customGuests', 'customGuestGender' ), 'customGuestGender', 'by alias' );
is( $r->lookup_table_field( 'customGuests', 'Guest Gender' )->{type}, 'list', 'a list column says so: its row values are option labels' );
is( $r->lookup_table_field( 'customGuests', 'Guest Birthdate' )->{type}, 'date', 'a date column says so' );

my $res = validate_mapping( $r, { tables => { guests => { table_alias => 'customGuests', columns => {
    first => 'Guest First Name', middle => 'Guest Middle Name', last => 'Guest Last Name',
    born  => 'Guest Birthdate',  gender => 'Guest Gender',      rel  => 'Guest Relationship' } } } } );
is_deeply( { map { $_ => $res->{tables}{guests}{columns}{$_}{alias} } keys %{ $res->{tables}{guests}{columns} } },
           { first => 'customGuestFirstName', middle => 'customGuestMiddleName', last => 'customGuestLastName',
             born => 'customGuestBirthdate', gender => 'customGuestGender', rel => 'customGuestRelationship' }, 'logical name -> row key, all six' );
{   my $e = err { validate_mapping( $r, { tables => { guests => { table_alias => 'customGuests', columns => { a => 'Passport', b => 'Visa' } } } } ) };
    like( $e, qr/\(2 errors\)/, 'two columns the table does not have' );
    like( $e, qr/columns: 'Guest First Name', 'Guest Middle Name', 'Guest Last Name', 'Guest Birthdate', 'Guest Gender', 'Guest Relationship'/, '...the error lists the six that exist (cleaned names)' ); }
{   my $path = "$dir/old.json";
    open my $fh, '>', $path or die;
    print {$fh} encode_json({ format => 2, loaded_at => time,
        fields => [ map { +{ id => "$_->{id}", name => $_->{name}, type => $_->{type}, alias => $_->{alias}, deprecated => 0 } } @{ fixture('meta-fields.json') } ],
        tables => { map { $_->{alias} => { alias => $_->{alias}, fields => [ map { +{ id => "$_->{id}", name => $_->{name}, alias => $_->{alias}, type => $_->{type} } } @{ $_->{fields} } ] } } @{ fixture('meta-tables.json') } } });
    close $fh;
    my $dead = Test::MockBambooHR->new;
    my $r2 = WebService::BambooHR::FieldRegistry->new( user_agent => $dead, cache_path => $path )->load;
    is( scalar @{ $dead->calls }, 0, 'cache from an earlier build is used, not refetched' );
    is( $r2->resolve_table_field( 'customGuests', 'Guest Middle Name' ), 'customGuestMiddleName', '...and the whitespace-tolerant lookup works against its un-cleaned names' ); }
done_testing;
