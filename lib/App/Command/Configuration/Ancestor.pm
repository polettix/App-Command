package App::Command::Configuration::Ancestor;
use strict;

sub get {
   my %args = @_;
   my ($fqn, $parent) = @args{qw< fqn parent >};
   my $conf;
   while ($parent && !$conf) {
      $conf = $parent->setup_for($fqn) if $parent->can('setup_for');
      $parent = $parent->has_parent ? $parent->parent : undef;
   } ## end while ($parent && !$conf)
   return {} unless $conf;
   return {
      map { $_ => $conf->{$_} }
      grep { exists $conf->{$_} }
      map { $_->{name} } @{$args{parameters} // []}
   };
} ## end sub get

1;
