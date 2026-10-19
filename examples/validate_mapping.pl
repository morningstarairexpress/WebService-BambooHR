#!/usr/bin/env perl
# Resolve every key in a mapping file against live BambooHR metadata and print what an application would use.
#   BAMBOO_COMPANY=acme BAMBOO_API_KEY=... perl examples/validate_mapping.pl examples/mapping.example.yaml
use 5.010; use strict; use warnings;
use FindBin qw( $Bin ); use lib "$Bin/../lib";
use YAML::XS qw( LoadFile );
use WebService::BambooHR;
use WebService::BambooHR::FieldRegistry;
use WebService::BambooHR::MappingValidator qw( validate_mapping request_fields );

my $path   = shift @ARGV or die "Usage: $0 <mapping.yaml>\n";
my $config = LoadFile($path);

# WebService::BambooHR::UserAgent is a Moo::Role consumed by WebService::BambooHR, so the client itself is the "user agent".
my $bamboo = WebService::BambooHR->new(
    company => $ENV{BAMBOO_COMPANY} // die("BAMBOO_COMPANY not set\n"),
    api_key => $ENV{BAMBOO_API_KEY} // die("BAMBOO_API_KEY not set\n"),
);
my $registry = WebService::BambooHR::FieldRegistry->new( user_agent => $bamboo )->load;    # no cache_path: memory only

my $r = eval { validate_mapping( $registry, $config ) };
if ($@) { print "FAILED\n\n$@"; exit 1 }

print "OK\n\nemployee fields (request by id; the value may come back under any of 'keys'):\n";
printf "  %-16s id %-6s alias %-24s keys: %s\n", $_, $r->{employee}{$_}{id}, $r->{employee}{$_}{alias} // '(none)', join( ' | ', @{ $r->{employee}{$_}{keys} } )
    for sort keys %{ $r->{employee} };
for my $name ( sort keys %{ $r->{tables} } ) {
    printf "\ntable '%s': alias %s (row data is keyed by column alias)\n", $name, $r->{tables}{$name}{alias};
    printf "  %-16s id %-6s alias %s\n", $_, $r->{tables}{$name}{columns}{$_}{id}, $r->{tables}{$name}{columns}{$_}{alias}
        for sort keys %{ $r->{tables}{$name}{columns} };
}
print "\nclient:  WebService::BambooHR->new( ..., custom_fields => request_fields(\$resolved->{employee}) )\n";
