package App::Command1::SubCommand;

use strict;
use warnings;
use Carp;
use English qw< -no_match_vars >;
use YAML;
use Log::Log4perl::Tiny qw< :easy :dead_if_first >;

use lib '.';
use lib '..';
use lib 'lib';
use lib '../lib';
use lib '../../lib';
use Moo;

extends 'App::Command';

sub BUILD_parameters {}
sub BUILD_help { return 'some subcommand' }
sub BUILD_children { return 0 }
sub BUILD_supports { return [qw<subcommand sub acommand> ]}

sub execute {
   my $self;
   INFO Dump($self->configuration());
   return;
}

1;
__END__

