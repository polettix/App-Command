package App::Command::Role::SetupProvider;

use strict;
use Moo::Role;
use namespace::autoclean;

requires qw< configuration >;

sub setup_for {
   my ($self, $name) = @_;
   my $cfg = $self->configuration('-setup') or return;
   return $cfg->{$name} if exists $cfg->{$name};
   return;
}

1;
