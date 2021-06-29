package App::Command1;

use strict;
use warnings;
use Carp;
use English qw< -no_match_vars >;
use Data::Dumper; $Data::Dumper::Indent = 1;
use Log::Log4perl::Tiny qw< :easy >;

use lib 'lib';
use lib '../lib';

use Sub::Identify;

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

sub BUILD_description {
   return <<'END_OF_DESCRIPTION';
This is a description for the top-level command.

Yes it is.

And here it is.
END_OF_DESCRIPTION
}

sub BUILD_configuration_files {
   my $self = shift;
   return [ $self->default_filenames() ];
}

sub BUILD_default_command { return 'show-foo' }

sub BUILD_sources { return [qw< +CmdLine +Environment +JSON +Default >] }

sub simple_commands {
   my $self = shift;
   return (
      {
         supports => ['show-foo', 'show_foo'],
         help => 'show the value of the foo option',
         description => 'Well, show that value!',
         execute  => sub {
            INFO "foo is ", $self->configuration('foo') ? 'true' : 'false';
         },
      }
   );
}

1;
