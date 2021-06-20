package App::Command::Role::Hierarchy;

use strict;
use Moo::Role;
use Log::Log4perl::Tiny qw< :easy :dead_if_first >;
use namespace::autoclean;

requires qw< load_class >;

has parent => (
   is => 'ro',
   lazy => 1,
   predicate => 'has_parent',
   weak_ref => 1,
);

has _children => (
   is => 'rwp',
   lazy => 1,
   builder => 'BUILD_children',
);

sub add_children {
   my $self = shift;
   return unless @_;
   my @children = @{$self->_children // []};
   push @children, @_;
   $self->_set__children(\@children);
   return;
}

sub autodiscover_children {
   my $self = shift;
   my $mypack = ref $self;
   (my $mypath = $mypack) =~ s{::}{/}gmxs;

   my @children;
   PATH:
   for my $prepath (@INC) {
      my $path = "$prepath/$mypath";
      if (opendir my $dh, $path) {
         push @children, map {
               (my $child = $_) =~ s/\.pm//mxs;
               $mypack . '::' . $child;
            }
            grep {
               my $fullpath = $path . '/' . $_;
               -f $fullpath && -r $fullpath && $fullpath =~ m{\.pm$}mxs;
            } readdir $dh;
         closedir $dh;
      }
      else {
         TRACE "autodiscover_children(): $path does not exist";
         next PATH;
      }
   }
   return @children;
}

sub BUILD_children { return [] }

sub children {
   my $self = shift;
   my @children = map {
      if (ref($_) eq 'CODE') {
         $_->($self); # expand
      }
      elsif (ref($_) eq 'HASH') {
         my ($class_name, $args) = %$_;
         my $class = $self->load_class($class_name);
         $class->new(%$args, parent => $self);
      }
      else { $_ } # leave unmodified
   } @{$self->_children() || []};
   $self->_set__children(\@children);
   return @children;
}

sub has_children { return scalar(shift->children) }

1;
