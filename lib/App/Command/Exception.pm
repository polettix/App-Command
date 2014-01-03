package App::Command::Exception;

use strict;
use warnings;
use Carp;
use English qw( -no_match_vars );

use Moo;

has status => (
   is => 'ro',
   lazy => 1,
   builder => 'BUILD_status',
);

has message => (
   is => 'ro',
   lazy => 1,
   builder => 'BUILD_message',
);

sub BUILD_status { return 'unsupported' }

sub BUILD_message {
   my $self = shift;
   return 'unsupported command' if $self->status() eq 'unsupported';
   return 'unspecified exception';
}

1;
__END__

