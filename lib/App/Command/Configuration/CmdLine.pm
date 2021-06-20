package App::Command::Configuration::CmdLine;
use strict;
use Log::Log4perl::Tiny qw< :easy :dead_if_first >;
use Getopt::Long ();

sub _default_getopt_config {
   my $has_children = shift;
   my @r = qw< gnu_getopt >;
   push @r, qw< require_order pass_through > if $has_children;
   return \@r;
}

sub get {
   my %args = @_;

   my $goc = $args{getopt_config}
      // _default_getopt_config($args{has_children});
   DEBUG "setting Getopt::Long configuration @$goc";
   Getopt::Long::Configure('default', @$goc);

   my @args = @{$args{input_args}};
   my %option_for;
   my @specs = map {
         my $go = $_->{getopt};
         ref($go) eq 'ARRAY'
         ? ( $go->[0] => sub { $go->[1]->(\%option_for, @_) } )
         : $go;
      }
      grep { exists $_->{getopt} }
      @{$args{parameters} // []};
   DEBUG "parsing command line (@args) with (@specs)";
   Getopt::Long::GetOptionsFromArray(\@args, \%option_for, @specs)
      or LOGDIE 'bailing out';

   DEBUG "options (@{[%option_for]})";
   DEBUG "residual arguments (@args)";

   # Check if we want to forbid the residual @args to start with a '-'
   my $strict = exists $args{restrict_residual_arguments}
      ? $args{restrict_residual_arguments}
      : 1;  # forbid by default
   if ($strict && @args && $args[0] =~ m{\A -}mxs) {
      Getopt::Long::Configure('default', 'gnu_getopt');
      Getopt::Long::GetOptionsFromArray(\@args, {});
      LOGDIE 'bailing out';
   }

   return (\%option_for, \@args);
}

1;
