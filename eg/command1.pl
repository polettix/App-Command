#!/usr/bin/env perl
use strict;
use warnings;
use English qw( -no_match_vars );
use lib '.';
use lib '../lib';

use App::Command1;

App::Command1->new()->run();
