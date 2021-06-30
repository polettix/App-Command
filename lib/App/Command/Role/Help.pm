package App::Command::Role::Help;

use strict;
use Moo::Role;
use Scalar::Util qw< blessed >;
use namespace::autoclean;

requires qw< args children has_children load_class parameters
   resolve_subcommand supports >;

has description => (
   is => 'ro',
   lazy => 1,
   builder => 'BUILD_description',
);

has help => (
   is => 'ro',
   lazy => 1,
   builder => 'BUILD_help',
);

sub BUILD_description { return }
sub BUILD_help { return 'Welp! Welp! There is no help!' }

sub _commandline_help {
   my ($getopt) = @_;
   $getopt = $getopt->[0] if ref($getopt) eq 'ARRAY';

   my @retval;

   my ($mode, $type, $desttype, $min, $max, $default);
   if (substr($getopt, -1, 1) eq '!') {
      $type = 'bool';
      substr $getopt, -1, 1, '';
      push @retval, 'boolean option';
   }
   elsif (substr($getopt, -1, 1) eq '+') {
      $mode = 'increment';
      substr $getopt, -1, 1, '';
      push @retval, 'incremental option (adds 1 every time it is provided)';
   }
   elsif ($getopt =~ s<(
         [:=])    # 1 mode
         ([siof]) # 2 type
         ([@%])?  # 3 desttype
         (?:
            \{
               (\d*)? # 4 min
               ,?
               (\d*)? # 5 max
            \}
         )? \z><>mxs) {
      $mode = $1 eq '=' ? 'mandatory' : 'optional';
      $type = $2;
      $desttype = $3;
      $min = $4;
      $max = $5;
      if (defined $min) {
         $mode = $min ? 'optional' : 'required';
      }
      $type = {
         s => 'string',
         i => 'integer',
         o => 'perl-extended-integer',
         f => 'float',
      }->{$type};
      my $line = "$mode $type option";
      $line .= ", at least $min times" if defined($min) && $min > 1;
      $line .= ", no more than $max times" if defined($max) && length($max);
      $line .= ", list valued" if defined($desttype) && $desttype eq '@';
      push @retval, $line;
   }
   elsif ($getopt =~ s<: (\d+) ([@%])? \z><>mxs) {
      $mode = 'optional';
      $type = 'i';
      $default = $1;
      $desttype = $2;
      my $line = "optional integer, defaults to $default";
      $line .= ", list valued" if defined($desttype) && $desttype eq '@';
      push @retval, $line;
   }
   elsif ($getopt =~ s<:+ ([@%])? \z><>mxs) {
      $mode = 'optional';
      $type = 'i';
      $default = 'increment';
      $desttype = $1;
      my $line = "optional integer, current value incremented if omitted";
      $line .= ", list valued" if defined($desttype) && $desttype eq '@';
      push @retval, $line;
   }

   my @alternatives = split /\|/, $getopt;
   if ($type eq 'bool') {
      push @retval, map {
         if (length($_) eq 1) { "-$_" }
         else { "--$_ | --no-$_" }
      } @alternatives;
   }
   elsif ($mode eq 'optional') {
      push @retval, map {
         if (length($_) eq 1) { "-$_ [<value>]" }
         else { "--$_ [<value>]" }
      } @alternatives;
   }
   else {
      push @retval, map {
         if (length($_) eq 1) { "-$_ <value>" }
         else { "--$_ <value>" }
      } @alternatives;
   }

   return @retval;
}

sub __name_for_parameter {
   my $p = shift;
   return $p->{name} if defined $p->{name};
   return $1 if defined $p->{getopt} && $p->{getopt} =~ m{\A(\w+)}mxs;
   return lc $p->{environment} if defined $p->{environment};
   return '~~~';
}

sub print_help {
   my $self = shift;
   my $fh = \*STDOUT;

   my (undef, @args) = $self->args;

   if (@args) {
      $self = $self->resolve_subcommand(@args)
         or die "unknown subcommand '$args[0]'\n";
   }

   my %args = @_;
   print {$fh} $self->help, "\n\n";

   if (defined (my $description = $self->description)) {
      $description =~ s{\A\s+|\s+\z}{}gmxs; # trim
      $description =~ s{^}{    }gmxs; # add some indentation
      print {$fh} "Description:\n$description\n\n";
   }

   printf {$fh} "Can be called as: %s\n\n", join ', ', $self->supports;

   my $parameters = $self->parameters;
   if (@$parameters) {
      print {$fh} "Options:\n";
      for my $parameter (@$parameters) {
         printf {$fh} "%15s: %s\n", __name_for_parameter($parameter), $parameter->{help} // '';

         if (exists $parameter->{getopt}) {
            my @lines = _commandline_help($parameter->{getopt});
            printf {$fh} "%15s  command-line: %s\n", '', shift(@lines);
            printf {$fh} "%15s                %s\n", '', $_ for @lines;
         }
         printf {$fh} "%15s  environment : %s\n", '', $parameter->{environment} // '*undef*'
            if exists $parameter->{environment};
         printf {$fh} "%15s  default     : %s\n", '', $parameter->{default} // '*undef*'
            if exists $parameter->{default};
      }
      print {$fh} "\n";
   }
   else {
      print {$fh} "This command has no options.\n\n";
   }

   if ($self->has_children) {
      print {$fh} "Sub commands:\n";
      $self->print_commands;
   }
   return;
}

sub print_commands {
   my $self = shift;
   my $fh = \*STDOUT;
   for my $child ($self->children) {
      my ($help, @aliases);
      if (ref($child) eq 'CODE') {
         ($help, @aliases) = $child->(help => 1, caller => $self);
      }
      elsif (ref($child) eq 'ARRAY') {
         ($help, @aliases) = $child->[0]->(
            help => 1,
            command_args => $child,
            caller => $self,
         );
      }
      else {
         my $object;
         if (blessed $child) {
            $object = $child;
         }
         else {
            my $class = $self->load_class($child);
            $object = $class->new(
               parent => $self,
               args => [],
            );
         }
         @aliases = $object->supports;
         $help = $object->help;
      }
      next unless @aliases;
      printf {$fh} "%15s: %s\n", shift(@aliases), $help;
      printf {$fh} "%15s  (also as: %s)\n", '', join ', ', @aliases
         if @aliases;
   }
   return;
}

1;
