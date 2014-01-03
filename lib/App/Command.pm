package App::Command;

# ABSTRACT: simplify command line applications generation

use strict;
use warnings;
use Carp;
use English qw< -no_match_vars >;
use Getopt::Long qw< GetOptionsFromArray >;

use Moo;
use Log::Log4perl::Tiny qw< :easy :dead_if_first >;
use YAML;
use Try::Tiny;
use App::Command::Exception;

has name => (
   is => 'ro',
   lazy => 1,
   builder => 'BUILD_name',
);

has _supports => (
   is => 'ro',
   lazy => 1,
   builder => 'BUILD_supports',
);

has parent => (
   is => 'ro',
   lazy => 1,
   predicate => 'has_parent',
);

has parameters => (
   is => 'ro',
   lazy => 1,
   builder => 'BUILD_parameters',
);

has getopt_config => (
   is => 'ro',
   lazy => 1,
   builder => 'BUILD_getopt_config',
);

has _children => (
   is => 'rwp',
   lazy => 1,
   builder => 'BUILD_children',
);

has configuration => (
   is => 'rw',
   lazy => 1,
   builder => 'BUILD_configuration',
);

has configuration_files => (
   is => 'ro',
   lazy => 1,
   builder => 'BUILD_configuration_files',
);

has args => (
   is => 'ro',
   lazy => 1,
   builder => 'BUILD_args',
);

has help => (
   is => 'ro',
   lazy => 1,
   builder => 'BUILD_help',
);

sub BUILD_getopt_config {
   my $self = shift;
   my @retval = 'gnu_getopt';
   push @retval, 'pass_through'
      if $self->has_children();
   return \@retval;
}

sub has_children {
   my $self = shift;
   my $children =()= $self->children();
   return $children;
}

sub parent_configuration {
   my $self = shift;
   return {} unless $self->has_parent();
   return $self->parent()->configuration();
}

sub root_configuration {
   my $self = shift;
   return {} unless $self->has_parent();
   my $parent = $self->parent();
   return $parent->configuration() unless $parent->has_parent();
   return $parent->root_configuration();
}

sub name_prefix { return 'App' }

sub BUILD_name {
   my $self = shift;
   my $name = ref $self;
   if (defined(my $prefix = $self->name_prefix())) {
      my $real_prefix = substr $name, 0, length $prefix;
      if ($real_prefix eq $prefix) {
         substr $name, 0, length($prefix), '';
         $name =~ s/^:*//mxs;
      }
   }
   return lc($name);
}

sub BUILD_supports {
   my $self = shift;
   (my $retval = $self->name()) =~ s/.*:://mxs;
   return $retval;
}

sub supports {
   my $self = shift;
   my $retval = $self->_supports();
   return $retval unless ref $retval;
   return @$retval;
}

sub default_filenames {
   my $self = shift;
   my $name = @_ ? shift : $self->name();
   return (
      "${name}rc",
      "${name}.conf",
      "$ENV{HOME}/.${name}rc",
      "$ENV{HOME}/.${name}.conf",
      "$ENV{HOME}/.${name}/config",
      "/etc/${name}rc",
      "/etc/${name}.conf",
      "/etc/${name}/config",
   );
}

sub BUILD_configuration_files { return [] }

sub BUILD_args { return [ @ARGV ] }

sub BUILD_children {
   my $self = shift;
   return {
      ready => [ $self->can('command_help'), $self->can('command_commands')],
      expand => [ $self->can('autodiscover_children') ],
   };
   return 0;
}

sub children {
   my $self = shift;
   my $children = $self->_children();

   # If set to false, no children for this command
   return unless $children;

   # If already a reference to an array, use it
   return @$children if ref($children) eq 'ARRAY';

   if (ref($children) eq 'HASH') {
      my @children = @{$children->{ready} // []};
      push @children, map {
         $_->($self);
      } @{$children->{expand} // []};
      $self->_set__children(\@children);
      INFO "expanded children @children";
      return @children;
   }
   
   # Perform autodiscovery
   $children = $self->autodiscover_children();
   $self->_set__children($children);
   return @$children;
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

sub BUILD_configuration {
   my $self = shift;
   my ($cmdline, $residual) = $self->configuration_from_args();
   my $env  = $self->configuration_from_environment();
   my $default = $self->configuration_from_default();
   my $merged = $self->hashes_merge(
      cmdline => $cmdline,
      environment => $env,
      default => $default,
   );

   if (my $other = $self->configuration_from_other($merged)) {
      $merged = $self->hashes_merge(
         cmdline => $cmdline,
         environment => $env,
         other => $other,
         default => $default,
      );
   }

   $merged->{args} = $residual;
   return $merged;
}

sub configuration_from_other {
   my $self = shift;
   my $rc = $self->root_configuration();
   return unless $rc;
   my $config = $rc->{merged};
   for my $chunk ($self->configuration_path_for_other()) {
      return unless exists $config->{$chunk};
      $config = $config->{$chunk};
   }
   return $config;
}

sub configuration_path_for_other {
   my $self = shift;
   return split /::/, $self->name();
}

sub hashes_merge {
   my $self = shift;

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

sub configuration_from_files {
   my $self = shift;
   my $merged = shift->{merged};
   my @files = exists($merged->{config})
      ? $merged->{config} : @{$self->configuration_files()};
   FILE:
   for my $file (@files) {
      INFO "checking file $file";
      next FILE unless -r $file;
      my $data = YAML::LoadFile($file);
      return $data;
   }
   return;
}

sub configuration_from_args {
   my $self = shift;

   Getopt::Long::Configure('default', @{$self->getopt_config()});

   my @input = @{$self->args()};
   my %output;
   my @specs = map { $_->{getopt} }
      grep { exists $_->{getopt} }
      @{$self->parameters() // []};
   GetOptionsFromArray(\@input, \%output, @specs)
      or LOGDIE 'bailing out';

   return (\%output, \@input);
}

sub configuration_from_environment {
   my $self = shift;
   return {
      map { $_->{name} => $ENV{$_->{environment}} }
      grep {
         exists($_->{environment}) && exists($ENV{$_->{environment}})
      }
      @{$self->parameters() // []}
   };
}

sub configuration_from_default {
   my $self = shift;
   return {
      map { $_->{name} => $_->{default} }
      grep { exists $_->{default} }
      @{$self->parameters() // []}
   };
}

sub run {
   my $self = shift;

   # Force parsing of command line
   my $configuration = $self->configuration();

   # Go
   return $self->execute(@_);
}

sub load_class {
   my ($self, $class) = @_;
   (my $path = $class . '.pm') =~ s{::}{/}gmxs;
   require $path;
   return $class;
}

sub dispatch {
   my $self = shift;
   my $configuration = $self->configuration();
   my ($subcommand, @args) = @{$configuration->{args}};
   my @children = $self->children()
      or LOGDIE 'no children in ' . $self->name() . "\n";
   for my $child (@children) {
      my $retval;
      try {
         my @parameters = (
            command => $subcommand,
            args    => \@args,
            caller  => $self,
         );
         if (ref($child) eq 'ARRAY') {
            $retval = $child->[0]->(
               @parameters,
               command_args => $child,
            );
         }
         elsif (ref($child) eq 'CODE') {
            $retval = $child->(@parameters);
         }
         else {
            my $class = $self->load_class($child);
            my $subcommand = $class->new(
               parent => $self,
               args => \@args,
            );
            die App::Command::Exception->new()
               unless $subcommand->does_support($subcommand);
            $retval = $subcommand->run(@parameters);
         }
         $retval //= 1;
      }
      catch {
         my $e = $_;
         my $message;
         if ($e->isa('App::Command::Exception')) {
            $message = $e->message()
               if $e->status() ne 'unsupported';
         }
         else {
            $message = $e;
         }
         ERROR $message if defined $message;
      };
      return $retval if defined $retval;
   }

   LOGDIE "subcommand '$subcommand' is not implemented\n";
}

sub does_support {
   my ($self, $command);
   return grep { $_ eq $command } $self->supports();
}

sub command_help {
   my %args = @_;
   my $self = $args{caller};
   return ('help on the command', 'help')
      if $args{help};
   die App::Command::Exception->new()
      unless $args{command} eq 'help';

   print $self->help(), "\n\n";

   printf "Can be called as: %s\n\n", join ', ', $self->supports();

   my $parameters = $self->parameters();
   if (@$parameters) {
      print "Parameters:\n";
      for my $parameter (@$parameters) {
         printf "%15s: %s\n", $parameter->{name}, $parameter->{help} // '';
         printf "%15s  command-line: %s\n", '', $parameter->{getopt}
            if exists $parameter->{environment};
         printf "%15s  environment : %s\n", '', $parameter->{environment}
            if exists $parameter->{environment};
         printf "%15s  default     : %s\n", '', $parameter->{default}
            if exists $parameter->{default};
      }
      print "\n";
   }

   if ($self->has_children()) {
      print "Commands:\n";
      command_commands(%args, command => 'commands');
   }
   return;
}

sub command_commands {
   my %args = @_;
   my $self = $args{caller};

   if ($args{help}) {
      return ('list of supported subcommands', 'commands')
         if $self->has_children();
      return;
   }
   die App::Command::Exception->new()
      unless ($args{command} eq 'commands') && $self->has_children();

   for my $child ($self->children()) {
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
         my $class = $self->load_class($child);
         my $object = $class->new(
            parent => $self,
            args => [],
         );
         @aliases = $object->supports();
         $help = $object->help();
      }
      next unless @aliases;
      printf {*STDOUT} "%15s: %s\n", shift(@aliases), $help;
      printf {*STDOUT} "%15s  (also as: %s)\n", '', join ', ', @aliases
         if @aliases;
   }
   
   return;
}

sub execute {
   my $self = shift;
   $self->dispatch(@_);
}


1;
__END__

=method BUILD_children

override to set the children. Can be:

=over

=item a reference to an array

that will contain the names of the packages that implement the children
commands

=item a true value

that is not a reference to an array, in which case autodiscovery of
children commands will be triggered (see L</autodiscover_children> for
a default implementation that is overrideable)

=item a false value

to mark a leaf command

=back

By default commands are considered leaves, i.e. you have to override this
method (e.g. by returning a I<simple> true value) to look for children
commands.

=method children

Get the list 

=method autodiscover_children

override to change how to autodiscover children commands
