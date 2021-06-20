package App::Command;

use strict;
{ our $VERSION = '0.001' }
use Moo;
use Scalar::Util qw< blessed >;
use Log::Log4perl::Tiny qw< :easy :dead_if_first >;
use Try::Catch qw< try catch >;
use namespace::autoclean;

with 'App::Command::Role::Name';
with 'App::Command::Role::Hierarchy';
with 'App::Command::Role::Configuration';
with 'App::Command::Role::Help';

has default_command => (
   is => 'ro',
   lazy => 1,
   builder => 'BUILD_default_command',
);

sub add_simple_children {
   my $self = shift;
   $self->add_children($self->generate_simple_commands(@_));
}

# Override from role
sub BUILD_children {
   my $self = shift;
   return [
      $self->can('generate_help_command'),
      $self->can('generate_commands_command'),
      sub {
         return unless $self->can('simple_commands');
         return $self->generate_simple_commands($self->simple_commands);
      },
      $self->can('autodiscover_children'),
   ];
   return 0;
}

sub BUILD_default_command { return 'help' }

sub dispatch {
   my $self = shift;
   my @children = $self->children()
      or LOGDIE 'no children in ' . $self->name() . "\n";

   my ($subcommand, @args) = $self->args;
   $subcommand //= $self->default_command;
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
            $message = $e->message if $e->status ne 'unsupported';
         }
         elsif (ref $e) {
            require JSON::PP;
            my $encoder = JSON::PP->new->ascii->pretty->allow_nonref;
            $message = $encoder->encode($e);
         }
         else {
            $message = $e;
         }
         LOGDIE $message if defined $message;
      };
      return $retval;
   }
   else {
      LOGDIE "subcommand '$subcommand' is not implemented\n";
   }
}

sub execute {
   my $self = shift;
   $self->dispatch(@_);
}

sub generate_help_command {
   my $self = shift;
   $self->generate_simple_commands(
      {
         help => 'help on the command',
         supports => ['help'],
         execute  => sub { $self->print_help() },
      },
   );
}

sub generate_commands_command {
   my $self = shift;
   $self->generate_simple_commands(
      {
         help => 'list of supported subcommands',
         supports => ['commands'],
         execute  => sub { $self->print_commands },
         parameters => [
            {
               name => 'alias',
               help => 'print all aliases for a command',
               getopt => 'alias|aliases!',
            },
         ],
      },
   );

}
sub generate_simple_commands {
   my $self = shift;
   require App::Command::Simple;
   return map { App::Command::Simple->new(%$_, parent => $self) } @_;
}

sub load_class {
   my ($self, $class) = @_;
   (my $path = $class . '.pm') =~ s{::}{/}gmxs;
   require $path;
   return $class;
}

sub resolve_subcommand {
   my $self = shift;
   my ($subcommand, @args) = @_;

   CHILD:
   for my $child ($self->children) {
      my $cmd = blessed($child) ? $child
         : $self->load_class($child)->new(parent => $self, args => \@args);
      return $cmd if $cmd->does_support($subcommand);
   }

   return;
}

sub run {
   my ($self, %args) = @_;

   $self = $self->new unless ref $self; # self-instantiate

   $self->input_args($args{args}) if exists $args{args};

   # Force parsing of command line
   DEBUG 'getting configuration (', $self->supports, ')';
   $self->bootstrap_configuration;

   # Go
   DEBUG 'calling execution (', $self->supports, ')';
   return $self->execute(%args);
}


1;
__END__
# 
# =method BUILD_children
# 
# override to set the children. Can be:
# 
# =over
# 
# =item a reference to an array
# 
# that will contain the names of the packages that implement the children
# commands
# 
# =item a true value
# 
# that is not a reference to an array, in which case autodiscovery of
# children commands will be triggered (see L</autodiscover_children> for
# a default implementation that is overrideable)
# 
# =item a false value
# 
# to mark a leaf command
# 
# =back
# 
# By default commands are considered leaves, i.e. you have to override this
# method (e.g. by returning a I<simple> true value) to look for children
# commands.
# 
# =method children
# 
# Get the list 
# 
# =method autodiscover_children
# 
# override to change how to autodiscover children commands
