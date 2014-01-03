package App::Command1;

use strict;
use warnings;
use Carp;
use English qw< -no_match_vars >;
use Data::Dumper; $Data::Dumper::Indent = 1;
use YAML;
use Log::Log4perl::Tiny qw< :easy >;

use lib 'lib';
use lib '../lib';

use Moo;
extends 'App::Command';

sub BUILD_parameters {
   return [
      {
         name => 'config',
         help => 'configuration file to load',
         getopt => 'config|c=s',
         environment => 'COMMAND1_CONFIG',
      },
      {
         name => 'foo',
         help => 'foo for bar',
         getopt => 'foo|f!',
         environment => 'COMMAND1_FOO',
         default => 1, # --no-foo
      },
   ];
}

sub BUILD_help {
   return 'some help text';
}

sub BUILD_configuration_files {
   my $self = shift;
   return [ $self->default_filenames() ];
}

sub configuration_from_other {
   my $self = shift;
   return $self->configuration_from_files(@_);
}

sub execute {
   my $self = shift;
   my $configuration = $self->configuration;
   INFO Dump($configuration);
   return $self->dispatch();
}


1;
__END__

