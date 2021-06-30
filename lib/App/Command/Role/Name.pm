package App::Command::Role::Name;

use strict;
use Moo::Role;
use namespace::autoclean;

has fqdn => (
   is => 'ro',
   lazy => 1,
   builder => 'BUILD_fqdn',
);

has name => (
   is => 'ro',
   lazy => 1,
   builder => 'BUILD_name',
);

has _supports => (
   is => 'ro',
   lazy => 1,
   builder => 'BUILD_supports',
   init_arg => 'supports',
);

sub BUILD_fqdn {
   my $self = shift;
   my @path = $self->name;
   unshift @path, $self->parent->fqdn
      if $self->can('parent') && $self->has_parent;
   return join '.', @path;
}

sub BUILD_name {
   my $self = shift;
   my $name = ref $self;
   if (defined(my $prefix = $self->name_prefix)) {
      my $plen = length $prefix;
      if ($prefix eq substr $name, 0, $plen) {
         substr $name, 0, $plen, '';
         $name =~ s{\A :* }{}mxs;
      }
   }
   return lc $name;
}

sub BUILD_supports { # default one is just the name
   (my $retval = shift->name) =~ s{.*::}{}mxs;
   return [$retval];
}

sub does_support {
   my ($self, $command) = @_;
   return grep { $_ eq $command } $self->supports;
}

sub name_prefix { return 'App' }

sub supports { return @{ shift->_supports } }

1;
