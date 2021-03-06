# NAME

App::Command - simplify command line applications generation

# VERSION

This document describes App::Command version {{\[ version \]}}.

# SYNOPSIS

In `lib/MyApp.pm`:

    package MyApp;
    use strict;
    use Moo;
    extends 'App::Command';
    
    sub BUILD_help { return 'this is a fantastic app' }
    sub BUILD_description { return 'it really is!'    }
    sub BUILD_parameters {
       return [
          {
             name => 'foo',
             help => 'foo for bar',
             getopt => 'foo|f!',
             environment => 'COMMAND1_FOO',
             default => 1, # --no-foo
          },
       ];
    }
    sub simple_commands {
       my $self = shift;
       return (
          {
             supports => [qw< show-foo show_foo >],
             help => 'show the value of the foo option',
             description => 'Well, show that value!',
             execute  => sub {
                print {*STDOUT} "foo is ",
                   $self->configuration('foo') ? 'true' : 'false';
                print {*STDOUT} "\n";
             },
          },
          {
             supports => [qw< roll die >],
             help => 'roll a die',
             description => 'roll a die, might be slightly biased though',
             parameters => [
                {
                   name => 'faces',
                   help => 'number of faces of the die',
                   getopt => 'faces|F=i',
                   environment => 'MYAPP_FACES',
                   default => 6,
                },
             ],
             execute => sub {
                my $faces = shift->configuration('faces');
                printf "%d\n", int(1 + rand $faces);
             },
          },
       );
    }

    1;

In `script/myapp`:

    use strict;
    use MyApp;
    MyApp->run(args => \@ARGV);

# DESCRIPTION

This library simplifies coding command-line applications, especially if they
should support sub-commands.

# COPYRIGHT AND LICENSE

Copyright (C) 2021 by Flavio Poletti <polettix@cpan.org>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

> [http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
