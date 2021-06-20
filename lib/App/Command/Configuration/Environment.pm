package App::Command::Configuration::Environment;
use strict;

sub get {
   my %args = @_;
   return {
      map { $_->{name} => $ENV{$_->{environment}} }
      grep {
         exists($_->{environment}) && exists($ENV{$_->{environment}})
      }
      @{$args{parameters} // []}
   };
}

1;
