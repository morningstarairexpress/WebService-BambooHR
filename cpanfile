requires 'perl', '5.010';

# upstream's own runtime dependencies (Throwable is required by Exception.pm: `with 'Throwable'`)
requires 'Moo', '>= 2.000000';
requires 'Throwable';
requires 'HTTP::Tiny', '>= 0.045';
requires 'Try::Tiny', '>= 0.13';
requires 'JSON::MaybeXS', '>= 1.003003';

on 'test' => sub {
    requires 'Test::More', '>= 0.88';
    requires 'LWP::Online';      # upstream's live tests (t/02-05)
};

recommends 'YAML::XS';           # examples/validate_field_mapping.pl only
