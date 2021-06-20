requires 'Moo';
requires 'Log::Log4perl::Tiny';
requires 'Try::Catch';
requires 'Params::Validate';
requires 'namespace::autoclean';

on develop => sub {
   requires 'Path::Tiny',          '0.084';
   requires 'Template::Perlish',   '1.52';
   requires 'Test::Pod::Coverage', '1.04';
   requires 'Test::Pod',           '1.51';
};
