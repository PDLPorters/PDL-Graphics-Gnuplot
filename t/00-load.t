#!perl

use Test::More tests => 1;

BEGIN {
    use_ok( 'PDL::Graphics::Gnuplot' ) || print "Bail out!\n";
}

diag( "Testing PDL::Graphics::Gnuplot $PDL::Graphics::Gnuplot::VERSION, Perl $], $^X" );
