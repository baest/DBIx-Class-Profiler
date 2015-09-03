package DBIx::Class::Profiler;
use strict;
use Time::HiRes qw(time);
use List::Util qw();
use feature 'state';

use base 'DBIx::Class::Storage::Statistics';

our $VERSION = '0.05';
my $caller_to_ignore = qr/^(?:DBIx::Class::|Try::Tiny|\(eval\)|Catalyst|Starman|Net::Server|Class::MOP|Plack|HTML::Mason::(?:Component|Request|Interp))/;

my $start;

sub new {
    my ($class, %params) = @_;

    my $setup = delete $params{setup};
    my $self = {print_caller=>1, caller_to_ignore => $caller_to_ignore, %params};
    bless $self, (ref($class) || $class);

    if ($setup) {
        die "setup arguments was provided, but the argument should be 'DBIx::Class::Storage', not " . ref($setup) unless $setup->isa('DBIx::Class::Storage');

        $setup->debugobj($self);
        $setup->debug(1);
    }

    return $self;
}

sub query_start {
    my ($self, $sql, @params) = @_;
    my @called_from;

    if ($self->{print_caller}) {
        my $caller_to_ignore = qr/$self->{caller_to_ignore}/;

        # stop examining stack at 200 deep
        my $level = 0;
        foreach my $i (0..200) {
            my @frame = caller($i);
            last unless @frame;

            next if $caller_to_ignore && $frame[0] =~ /$caller_to_ignore/;
            next if $frame[0] =~ /HTML::Mason::Commands/ && $frame[1] =~ /\.obj$/;

            push @called_from, "Method: $frame[0] at line $frame[2] in $frame[1]";

            last if ++$level >= $self->{print_caller};
        }
    }
    my $params = join(', ', @params);
    if ($self->{statements}{$sql}) {
        $self->{statements}{$sql}{count}++;
        $self->{statements}{$sql}{params}{$params}++;
    }
    else {
        $self->{statements}{$sql} = {
            count => 1,
            params => {
                $params => 1,
            },
            total_time => 0.0
        };
    }
    if (@called_from) {
        my $called_from = join("\n\t", @called_from);
        $self->{statements}{$sql}{called_from}{$called_from}++;
    }

    $start = time();
}

sub query_end {
    my ($self, $sql, @params) = @_;

    my $elapsed = sprintf("%0.4f", time() - $start);
    $self->{statements}{$sql}{total_time} += $elapsed;
    $start = undef;
}

sub report {
    my ($self, $show_params) = @_;
    my $total_time = 0.0;
    my @report;

    foreach my $sql (sort { $self->{statements}{$a}{total_time} <=> $self->{statements}{$b}{total_time} } keys %{$self->{statements}}) {
        push @report, sprintf("Executed\n\t%s\n%d times (with %d different parameters%s). Total time was %0.4f secs (%0.4f secs per call)%s", 
                $sql, 
                $self->{statements}{$sql}{count}, 
                scalar(keys %{$self->{statements}{$sql}{params}}),
                ($show_params) ? (' (' . join('; ', keys %{$self->{statements}{$sql}{params}}) . ')') : '',
                $self->{statements}{$sql}{total_time},
                $self->{statements}{$sql}{total_time} / $self->{statements}{$sql}{count},
                (($self->{print_caller}) ? "\nCalled from:\n\t" . join("\n\n\t", map { "$_ ($self->{statements}{$sql}{called_from}{$_} time(s))" } keys %{$self->{statements}{$sql}{called_from}}) : ''),
        );


        $total_time += $self->{statements}{$sql}{total_time};
    }

     push @report, sprintf("Total time spent doing queries: %0.4f secs", $total_time);

     return wantarray() ? @report : join("\n\n", @report) . "\n\n";
}

sub print_report {
    my $self = shift;
    $self->print(scalar($self->report(@_)));
}

sub query_count {
    my $self = shift;
    return List::Util::sum(map { $self->{statements}->{$_}->{count} } keys %{$self->{statements}});
}

sub txn_begin { }
sub txn_rollback{ }
sub txn_commit{ }

"Profiling for profit";

__END__

=head1 NAME

DBIx::Class::Profiler - simple profilling tool for DBIx::Class. Will print every different type of query along with how many times it was called and with total execution time

=head1 SYNOPSIS

 # easy setup of profilling
 use DBIx::Class::Profiler;
 my $prof = DBIx::Class::Profiler->new(setup => $c->model('NzDB')->schema->storage);

 # setup profilling the hard way
 use DBIx::Class::Profiler;
 my $prof = DBIx::Class::Profiler->new();
 $c->model('NzDB')->schema->storage->debugobj($prof);
 $c->model('NzDB')->schema->storage->debug(1);

 # do actual DB work...
 $rs = $c->model('NzDB')->schema->txn_do($transaction);

 # print report
 $prof->print_report();

 # above will print out something like the following:
 Executed 
    SELECT "me"."id", "me"."updated", "me"."cached_columns", "me"."version" FROM "cache"."displaytaxonomynode" "me" WHERE ( "me"."id" = ? )
 165 times (with 165 different parameters). Total time was 0.1306 secs (0.0008 secs per call)

 Executed
    SELECT "me"."id", "me"."tag", "me"."class", "me"."created", "me"."updated", "me"."created_initials", "me"."updated_initials" FROM "construct"."tag" "me" WHERE ( ( "me"."class" = ? AND "me"."tag" = ? ) )
 165 times (with 1 different parameters). Total time was 0.1735 secs (0.0011 secs per call)
 
 Executed 
    SELECT "me"."id", "me"."taxonomynode_id", "me"."tag_id", "me"."created", "me"."created_initials", "me"."updated", "me"."updated_initials", "me"."exclude_tag" FROM "construct"."tagtaxonomynode" "me" WHERE ( ( "me"."tag_id" = ? AND "me"."taxonomynode_id" = ? ) )
 165 times (with 165 different parameters). Total time was 0.1859 secs (0.0011 secs per call)
 
 Executed 
    INSERT INTO "workqueue"."job" ( "arg", "coalesce", "funcid", "grabbed_until", "priority", "run_after") VALUES ( ?, ?, ?, ?, ?, ? ) RETURNING "jobid"
 330 times (with 330 different parameters). Total time was 0.3572 secs (0.0011 secs per call)
 
 Total time spent doing queries: 0.8472 secs


=head1 DESCRIPTION

This module setups profiling for DBIx::Class and measures how much time is used doing every group of queries. Queries are grouped by their ?-form. Furthermore it returns the total amount of time doing queries. Query time is without DBIx::Class overhead of changing the resultsets into classes, but some of the other DBIx::Class overhead along with normal DBI overhead.

Transactions are ignored.

=head1 INTERFACE

=head2 new()

Creates as new profiler... Take the following parameters (as a hash):

=over

=item setup

A DBIx::Class::Storage object which is used for setting up the profiler

=item print_caller

Integer (default to 1), print where each SQL was called from (stacktrace where the integer given denotes how deep we print the trace). The heurestic is pretty simple, just skip DBIx::Class, Try::Tiny, eval and others until we reach something that looks like caller code. The things skipped aren't counted against the level.

=back

=head2 report($show_param)

Returns a array or string of report. In scalar mode every output query is seperated by 2 \n. If $show_param is true then all params are printed (lots of output with many different parameters to the calls)

=head2 print_report($show_param)

Print the $self->report using DBIx::Class::Storage::Statistics::print

=head2 query_count

Returns the total number of queries.

=head1 DEPENDENCIES

L<Time::HiRes>, L<DBIx::Class::Storage::Statistics>

=head1 AUTHOR

Martin Kjeldsen C<< <mfk@novozymes.com> >>

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2014, Novozymes. All Rights Reserved.

=cut
