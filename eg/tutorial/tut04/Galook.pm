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

sub execute {
   my $self = shift;
   return $self->dispatch if $self->args;
   INFO "foo is ", $self->configuration('foo') ? 'true' : 'false';
}

1;
