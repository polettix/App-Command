package Galook;
use Moo;
use Log::Log4perl::Tiny qw< :easy :dead_if_first >;
extends 'App::Command';

sub BUILD_help { 'galook your foos' }

sub BUILD_description {
   return <<'END';
This is some description.

On multiple lines, I mean.

Here it ends the description.
END
}

sub BUILD_parameters {
   return [
      {
         name        => 'config',
         help        => 'path to the configuration file',
         getopt      => 'config|c=s',
         environment => 'GALOOK_CONFIG',
         default     => undef,
      },
      {
         name        => 'foo',
         help        => 'foo for bar',
         getopt      => 'foo|f!',
         environment => 'GALOOK_FOO',
         default     => 1,               # --no-foo
      },
   ];
} ## end sub BUILD_parameters

sub BUILD_sources { return [qw< +CmdLine +Environment +JSON +Default >] }

sub simple_commands {
   return (
      {
         supports => [qw< date now >],
         help => 'show the current date and time',
         description => 'Print date and time for... now',
         parameters => [
            {
               name => 'gm',
               help => 'use GMT instead of local',
               getopt => 'gm!',
               environment => 'GALOOK_DATE_GM',
               default => 0,
            },
         ],
         execute  => sub {
            my $self = shift;
            my $now = $self->c('gm') ? gmtime() : localtime();
            print {*STDOUT} $now, "\n";
         },
      },
      {
         supports => [qw< show-foo >],
         help => 'show the current value for parameter foo',
         description => 'foo can be true or false... show it!',
         execute => sub {
            my $self = shift;
            INFO "foo is ", $self->configuration('foo') ? 'true' : 'false';
         },
      },
   );
}

1;
