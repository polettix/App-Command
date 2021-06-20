#!/usr/bin/env perl
use strict;
use warnings;
use English qw( -no_match_vars );
use lib '.';
use lib '../lib';

use Log::Log4perl::Tiny qw< :easy LOGLEVEL :no_extra_logdie_message >;

#LOGLEVEL 'DEBUG';

use App::Command1;

App::Command1->new()->run(args => \@ARGV);
