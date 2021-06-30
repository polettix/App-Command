package Galook::Gurgle;
use Moo;
use Log::Log4perl::Tiny qw< :easy :dead_if_first >;
extends 'App::Command';

sub BUILD_help { 'gurgle your galooks' }

sub execute {
   print {*STDOUT} "Gurgle! A Galook is in town!\n";
}

1;
