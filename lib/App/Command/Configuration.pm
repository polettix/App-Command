package App::Command::Configuration;

use strict;
use Moo;
use Params::Validate ();
use App::Command::Exception;
use namespace::autoclean;

has _args => (is => 'ro', required => 1, init_arg => 'args');
has _cfg  => (is => 'ro', required => 1, init_arg => 'configuration');

sub create {
   my ($package, %args) = @_;

   # Each source might have its own setup parameters, kept here
   my $ssf = $args{source_setup_for} // {};

   # This is for merging hashes, it can be overridden from the outside
   my $hashes_merger = $args{hashes_merger} // \&__hashes_merge;

   # As we progress, we keep $merged updated with the merge of all sources
   # in order. This allows later sources to leverage previous ones, e.g.
   # for loading configuration files based on command-line options
   my @sequence;
   my $configuration = {};

   # This will keep all "non-option" arguments that we collect along the
   # way. They should only come from command line, but who knows?
   my @residual_args;

   for my $source (@{$args{sources}}) {
      my $srcpack = $source;
      $srcpack = $package . '::' . $1 if $source =~ m{\A \+ (.*)}mxs;
      (my $path = $srcpack . '.pm') =~ s{::}{/}gmxs;
      require $path;

      my ($opts, $residual_args) = $srcpack->can('get')->(
         %{$ssf->{$source} // {}},
         %args,
         configuration => $configuration->{merged},
      );

      push @residual_args, @$residual_args if defined $residual_args;

      push @sequence, $source, $opts;
      $configuration = $hashes_merger->(@sequence);
   }

   my $validator = $args{validator} // sub { return };
   $validator = __validator($validator) if ref($validator) ne 'CODE';
   $validator->($configuration);

   return $package->new(
      args => \@residual_args, 
      configuration => $configuration,
   );
}

sub args { return @{shift->_args // []} }

sub check_and_get {
   my ($self, $name) = @_;
   my $merged = $self->_cfg->{merged};
   return exists($merged->{$name}) ? (yes => $merged->{$name}) : ();
}

sub __hashes_merge {
   my @inputs = @_;
   my (%merged, %source_for);
   while (@inputs) {
      my ($name, $config) = splice @inputs, 0, 2;
      while (my ($key, $value) = each %$config) {
         next if exists $merged{$key};
         $merged{$key} = $value;
         $source_for{$key} = $name;
      }
   }

   return {inputs => [ @_ ], source => \%source_for, merged => \%merged};
}

sub __validator {
   my $validator = shift;
   return sub {
      my $configuration = shift;
      Params::Validate::validation_options(
         on_fail => sub {
            die App::Command::Exception->new(
               status => 'validation failure',
               message => shift,
            );
         }
      );
      my @opts = %{$configuration->{merged}};
      Params::Validate::validate(@opts, $validator);
   };
}

1;
