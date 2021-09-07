#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use PDL;
use PDL::Graphics::Gnuplot;
use IPC::Cmd qw(can_run);
use Proc::ProcessTable;

unless ( $ENV{RELEASE_TESTING} ) {
    plan( skip_all => "Author tests not required for installation" );
}

if( can_run('xdotool') && $PDL::Graphics::Gnuplot::valid_terms->{qt} ) {
    plan tests => 1;
} else {
    plan skip_all => 'Missing xdotool or missing Gnuplot qt terminal';
}

sub get_gnuplot_qt_windows {
    get_gnuplot_by_class('gnuplot_qt');
}

sub get_gnuplot_by_class {
    my ($class) = @_;
    chomp( my $window_ids = `xdotool search --class $class` );
    my @id = split "\n", $window_ids;
    my @names = map {
        chomp(my $name = `xdotool getwindowname $_`);
        $name;
    } @id;
}

subtest "qt terminal created and closed" => sub {
    is scalar get_gnuplot_qt_windows(), 0, 'No initial gnuplot_qt windows';
    my $w = gpwin('qt');
    my $x = zeroes(50)->xlinvals(0, 7);
    $w->plot(with => 'lines', $x, $x->sin);
    is scalar get_gnuplot_qt_windows(), 1, 'Created a single qt window';
    $w->_printGnuplotPipe( 'main', "set term qt 0 close\n");
    $w->close;
    my @windows = get_gnuplot_qt_windows();
    use DDP; p @windows;
    is scalar get_gnuplot_qt_windows(), 0, 'Created a single qt window';
};

done_testing;
