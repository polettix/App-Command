package App::Command;

# ABSTRACT: simplify command line applications generation

use strict;
use warnings;
use Carp;
use English qw< -no_match_vars >;
use Getopt::Long qw< GetOptionsFromArray >;
use Scalar::Util qw< blessed >;

use Moo;
use Log::Log4perl::Tiny qw< :easy :dead_if_first >;
use YAML;
use Try::Tiny;
use App::Command::Exception;
use Params::Validate ();

has name => (
   is => 'ro',
   lazy => 1,
   builder => 'BUILD_name',
);

has _supports => (
   is => 'ro',
   lazy => 1,
   builder => 'BUILD_supports',
   init_arg => 'supports',
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
   is => 'rw',
   lazy => 1,
   builder => 'BUILD_args',
);

has help => (
   is => 'ro',
   lazy => 1,
   builder => 'BUILD_help',
);

has validator => (
   is => 'ro',
   lazy => 1,
   builder => 'BUILD_validator',
);

sub BUILD_validator { return }

sub BUILD_parameters { return [] }

sub BUILD_getopt_config {
   my $self = shift;
   my @retval = 'gnu_getopt';
   push @retval, qw< require_order pass_through >
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

sub root {
   my $self = shift;
   return $self unless $self->has_parent();
   return $self->parent()->root();
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
   return [
      $self->can('generate_help_command'),
      $self->can('generate_commands_command'),
      sub {
         return unless $self->can('simple_commands');
         return $self->generate_simple_commands($self->simple_commands());
      },
      $self->can('autodiscover_children'),
   ];
   return 0;
}

sub children {
   my $self = shift;
   $self->_normalize_children();
   return @{$self->_children()};
}

sub _normalize_children {
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
}

sub add_children {
   my $self = shift;
   return unless @_;
   my @children = @{$self->_children() // []};
   push @children, @_;
   $self->_set__children(\@children);
   return;
}

sub add_simple_children {
   my $self = shift;
   $self->add_children($self->generate_simple_commands(@_));
}

sub generate_simple_commands {
   my $self = shift;
   require App::Command::Simple;
   return map { App::Command::Simple->new(%$_, parent => $self) } @_;
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
      DEBUG "checking file $file";
      next FILE unless -r $file;
      my $data = YAML::LoadFile($file);
      return $data;
   }
   return;
}

sub configuration_from_args {
   my $self = shift;

   DEBUG "setting Getopt::Long configuration @{$self->getopt_config()}";
   Getopt::Long::Configure('default', @{$self->getopt_config()});

   my @input = @{$self->args()};
   my %output;
   my @specs = map {
         my $go = $_->{getopt};
         ref($go) eq 'ARRAY'
         ? ( $go->[0] => sub { $go->[1]->(\%output, @_) } )
         : $go;
      }
      grep { exists $_->{getopt} }
      @{$self->parameters() // []};
   DEBUG "parsing command line with @specs";
   GetOptionsFromArray(\@input, \%output, @specs)
      or LOGDIE 'bailing out';

   DEBUG "residual parameters: @input";

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

sub validate {
   my $self = shift;
   my $validator = $self->validator() or return;
   my $configuration = $self->configuration();
   Params::Validate::validation_options(on_fail => sub {
      die App::Command::Exception->new(
         status => 'validation failure',
         message => shift,
      );
   });
   my @parameters = %{$configuration->{merged}};
   Params::Validate::validate(@parameters, $validator);
}

sub run {
   my $self = shift;
   my %setup = @_;

   $self->args($setup{args}) if exists $setup{args};

   # Force parsing of command line
   DEBUG 'getting configuration (', $self->supports(), ')';
   my $configuration = $self->configuration();

   # Validate configuration... if it makes sense
   $self->validate();

   # Go
   DEBUG 'calling execution (', $self->supports(), ')';
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
   my @children = $self->children()
      or LOGDIE 'no children in ' . $self->name() . "\n";

   my $configuration = $self->configuration();
   my ($subcommand, @args) = @{$configuration->{args}};
   $subcommand //= 'help';
   DEBUG "dispatching to $subcommand with arguments @args";

   if (my $cmd = $self->resolve_subcommand($subcommand, @args)) {
      my $retval;
      try {
         $retval = $cmd->run(
            command => $subcommand,
            args    => \@args,
            caller  => $self,
         ) // 1;
      }
      catch {
         my $e = $_;
         my $message;
         if (blessed($e) && $e->isa('App::Command::Exception')) {
            $message = $e->message()
               if $e->status() ne 'unsupported';
         }
         elsif (ref $e) {
            $message = YAML::Dump($e);
         }
         else {
            $message = $e;
         }
         LOGDIE $message if defined $message;
      };
      return $retval if defined $retval;
   }
   else {
      LOGDIE "subcommand '$subcommand' is not implemented\n";
   }
}

sub does_support {
   my ($self, $command) = @_;
   return grep { $_ eq $command } $self->supports();
}

sub add_help_command {
   my $self = shift;
   $self->add_simple_children($self->generate_help_command());
}

sub generate_help_command {
   my $self = shift;
   $self->generate_simple_commands({
      help => 'help on the command',
      supports => ['help'],
      execute  => sub { $self->_command_help() },
   });
}

sub resolve_subcommand {
   my $self = shift;
   my ($subcommand, @args) = @_;

   CHILD:
   for my $child ($self->children()) {
      my $cmd = blessed($child) ? $child
         : $self->load_class($child)->new(parent => $self, args => \@args);
      return $cmd if $cmd->does_support($subcommand);
   }

   return;
}

sub _commandline_help {
   my ($getopt) = @_;

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

sub _command_help {
   my $self = shift;

   my $target = $self;
   my (undef, @args) = @{$self->configuration()->{args}};

   if (@args) {
      $self = $self->resolve_subcommand(@args)
         or die "unknown subcommand '$args[0]'\n";
   }

   my %args = @_;
   print $self->help(), "\n\n";

   printf "Can be called as: %s\n\n", join ', ', $self->supports();

   my $parameters = $self->parameters();
   if (@$parameters) {
      print "Parameters:\n";
      for my $parameter (@$parameters) {
         printf "%15s: %s\n", $parameter->{name}, $parameter->{help} // '';

         if (exists $parameter->{getopt}) {
            my @lines = _commandline_help($parameter->{getopt});
            printf "%15s  command-line: %s\n", '', shift(@lines);
            printf "%15s                %s\n", '', $_ for @lines;
         }
         printf "%15s  environment : %s\n", '', $parameter->{environment}
            if exists $parameter->{environment};
         printf "%15s  default     : %s\n", '', $parameter->{default}
            if exists $parameter->{default};
      }
      print "\n";
   }

   if ($self->has_children()) {
      print "Sub commands:\n";
      $self->_command_commands();
   }
   return;
}

sub add_commands_command {
   my $self = shift;
   $self->add_simple_children($self->generate_commands_command());
}

sub generate_commands_command {
   my $self = shift;
   $self->generate_simple_commands({
      help => 'list of supported subcommands',
      supports => ['commands'],
      execute  => sub { $self->_command_commands() },
   });
}

sub _command_commands {
   my $self = shift;
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
