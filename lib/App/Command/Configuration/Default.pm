package App::Command::Configuration::Default;
use strict;

sub get {
   my %args = @_;
   return {
      map { $_->{name} => $_->{default} }
      grep { exists $_->{default} }
      @{$args{parameters} // []}
   };
}

1;
