package Galook;
use Moo;
use Log::Log4perl::Tiny qw< :easy :dead_if_first >;
extends 'App::Command';

sub BUILD_parameters {
   return [
      {
         name => 'foo',
         help => 'foo for bar',
         getopt => 'foo|f!',
         environment => 'GALOOK_FOO',
         default => 1, # --no-foo
      },
   ];
}

sub execute {
   my $self = shift;
   INFO "foo is ", $self->configuration('foo') ? 'true' : 'false';
}

1;
