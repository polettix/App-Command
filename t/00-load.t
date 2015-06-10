use Test::More tests => 3;

BEGIN {
   use_ok('App::Command');
   use_ok('App::Command::Simple');
   use_ok('App::Command::Exception');
}

diag("Testing App::Command $App::Command::VERSION");
done_testing();
