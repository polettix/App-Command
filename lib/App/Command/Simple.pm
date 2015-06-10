package App::Command::Simple;

# ABSTRACT: class for executing 'simple' commands

use strict;
use warnings;
use Carp;
use English qw< -no_match_vars >;
use Log::Log4perl::Tiny qw< :easy :dead_if_first >;

use Moo;
extends 'App::Command';

has execute_sub => (
   is => 'ro',
   required => 1,
   init_arg => 'execute',
);

sub BUILD_children { return [] }

sub execute {
   my $self = shift;
   $self->execute_sub()->($self, @_);
}

1;
__END__

