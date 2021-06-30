package App::Command::Role::Configuration;

use strict;
use Moo::Role;
use Log::Log4perl::Tiny qw< :easy :dead_if_first >;
use namespace::autoclean;

requires qw< fqn has_children has_parent parent >;

has _configuration => (
   is => 'ro',
   lazy => 1,
   builder => 'BUILD_configuration',
   init_arg => 'configuration', # for esoteric stuff
);

has configuration_class => (
   is => 'ro',
   lazy => 1,
   builder => 'BUILD_configuration_class',
);

has input_args => (
   init_arg => 'args',
   is => 'rw',
   lazy => 1,
   builder => 'BUILD_input_args',
);

has parameters => (
   is => 'ro',
   lazy => 1,
   builder => 'BUILD_parameters',
);

has sources => (
   is => 'ro',
   lazy => 1,
   builder => 'BUILD_sources',
);

has source_setup_for => (
   is => 'ro',
   lazy => 1,
   builder => 'BUILD_source_setup_for',
);

has validator => (
   is => 'ro',
   lazy => 1,
   builder => 'BUILD_validator',
);

sub args { return shift->_configuration->args }

sub bootstrap_configuration { shift->_configuration; return }

sub BUILD_configuration {
   my $self = shift;
   my $class = $self->configuration_class;
   (my $path = $class . '.pm') =~ s{::}{/}gmxs;
   require $path;
   return $class->create(
      fqn          => $self->fqn,
      has_children => $self->has_children,
      input_args   => $self->input_args,
      parameters   => $self->parameters,
      parent       => ($self->has_parent ? $self->parent : undef),
      sources      => $self->sources,
      source_setup_for => $self->source_setup_for,
      validator    => $self->validator,
   );
}

sub BUILD_configuration_class { return 'App::Command::Configuration' }
sub BUILD_input_args { return [] }
sub BUILD_parameters { return [] }
sub BUILD_sources { return [qw< +CmdLine +Environment +Default >] }
sub BUILD_source_setup_for { return {} }
sub BUILD_validator { return }

sub complete_configuration {
   require Storable;
   return Storable::dclone(shift->_configuration);
}

sub c { return shift->configuration(@_) }

sub configuration {
   my ($self, $name, %opts) = @_;

   my $climb = exists $args{parent} ? $args{parent} : 1;

   my $node = $self;
   while (defined $node) {
      my ($exists, $value) = $node->_configuration->check_and_get($name);
      return $value if $exists;
      last unless $climb && $node->has_parent;
      $node = $node->parent;
   }

   my $default = $args{default};
   return $default->(@_) if ref($default) eq 'CODE';
   return $default;
}

1;
