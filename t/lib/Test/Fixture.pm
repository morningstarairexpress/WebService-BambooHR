package Test::Fixture;
# Fixtures live in t/data/. Every name and value in them is invented; they reproduce the *shapes and quirks* the BambooHR
# API was observed to have (see t/data/README.md).
use strict; use warnings; use FindBin qw( $Bin ); use JSON::MaybeXS ();
use Exporter 'import'; our @EXPORT_OK = qw( fixture_text fixture );
sub fixture_text { my $n = shift; open my $fh, '<', "$Bin/data/$n" or die "fixture $n: $!"; local $/; my $s = <$fh>; return $s }
sub fixture      { return JSON::MaybeXS::decode_json( fixture_text(@_) ) }
1;
