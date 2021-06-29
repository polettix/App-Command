package App::Command::Configuration::JSON;
use strict;
use Log::Log4perl::Tiny qw< :easy :dead_if_first >;
use JSON::PP 'decode_json';

sub load {
   my $filename = shift;
   open my $fh, '<:encoding(UTF-8)', $filename
      or LOGCROAK "cannot open('$filename'): $!";
   local $/;
   my $json = <$fh>;
   close $fh;
   return decode_json($json);
}

sub loader {
   my %largs = @_;
   my $field_name = $largs{field_name};
   my @default_paths = @{$largs{default_paths} || []};
   return sub {
      my %args = @_;
      my $conf;
      if (defined($field_name) && defined($args{configuration}{$field_name})) {
         $conf = load($args{configuration}{$field_name});
      }
      else {
         for my $filename (@default_paths) {
            next unless -e $filename;
            $conf = load($filename);
         }
         return {} unless $conf;
      }
      my %retval =
         map { $_ => $conf->{$_} }
         grep { exists $conf->{$_} }
         map { $_->{name} } @{$args{parameters} // []};
      for my $key (keys %$conf) {
         next unless $key =~ m{\A -}mxs;
         $retval{$key} = $conf->{$key};
      }
      return \%retval;
   };
}

sub get { return loader(field_name => 'config')->(@_) }

1;
