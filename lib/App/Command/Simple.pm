package App::Command::Simple;

# ABSTRACT: class for executing 'simple' commands

use strict;
use Moo;
use Log::Log4perl::Tiny qw< :easy :dead_if_first >;
use namespace::autoclean;

extends 'App::Command';

has execute_sub => (
   is => 'ro',
   required => 1,
   init_arg => 'execute',
);

sub BUILD_name {
   my $self = shift;
   my ($main) = $self->supports;
   return $main unless $self->has_parent;
   return $self->parent->name . '~' . $main;
}

sub BUILD_children { return [] }

sub execute {
   my $self = shift;
   $self->execute_sub()->($self, @_);
}

1;
