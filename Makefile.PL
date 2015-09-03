use strict;
use warnings;
 
use ExtUtils::MakeMaker;

WriteMakefile(
  "AUTHOR" => "Martin Kjeldsen <m\@urth.org>",
  "LICENSE" => "artistic_2",
  "NAME" => "DBIx::Class::Profiler",
	VERSION_FROM      => "lib/DBIx/Class/Profiler.pm",
  "PREREQ_PM" => {
    "List::Util" => 0,
    "Time::HiRes" => 0,
    "DBIx::Class" => 0,
  },
);
