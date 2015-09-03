use strict;
use Test::More tests => 1;
 
BEGIN { use_ok 'DBIx::Class::Profiler' }
diag "Perl/$^V";
diag "DBIx::Class::Profiler/$DBIx::Class::Profiler::VERSION";
