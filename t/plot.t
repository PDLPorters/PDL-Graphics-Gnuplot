#!perl

use Test::More tests => 156;

BEGIN {
    use_ok( 'PDL::Graphics::Gnuplot', qw(plot) ) || print "Bail out!\n";
}

use File::Temp qw(tempfile);
use PDL;
eval "use PDL::Graphics::Gnuplot;";

##########
# Uncomment these to test error handling on Microsoft Windows, from within POSIX....
# $PDL::Graphics::Gnuplot::debug_echo = 1;
# $PDL::Graphics::Gnuplot::MS_io_braindamage = 1;

ok( !$@, "loaded the module with no error\n");

$ENV{GNUPLOT_DEPRECATED} = 1;   # shut up deprecation warnings
eval { $w=gpwin() };

ok( (!$@ and defined($w) and ref($w) =~m/PDL::Graphics::Gnuplot/), 
    "Constructor created a plotting object" );

ok(length($PDL::Graphics::Gnuplot::gp_version), "Extracted a version string from gnuplot");

diag( "\nP::G::G v$PDL::Graphics::Gnuplot::VERSION, gnuplot v$PDL::Graphics::Gnuplot::gp_version, Perl v$], $^X on $^O #\n" );

my $x = sequence(5);

##############################
#
our (undef, $testoutput) = tempfile('pdl_graphics_gnuplot_test_XXXXXXX');

{
  # test basic plotting
  eval{ plot ( {terminal => 'dumb 79 24', output => $testoutput}, $x); };


  ok(! $@,           'basic plotting succeeded without error' )
    or diag "plot() died with '$@'";

  ok(-e $testoutput, 'basic plotting created an output file' )
    or diag "plot() didn't create an output file";

  # call the output good if it's at least 80% of the nominal size
  my @filestats = stat $testoutput;
  ok($filestats[7] > 79*24*0.8, 'basic plotting created a reasonably-sized file')
    or diag "resulting output file should be ascii 79x24, but only contains $filestats[7] bytes";

  PDL::Graphics::Gnuplot::restart();

  unlink($testoutput) or warn "\$!: $!";
}

ok($PDL::Graphics::Gnuplot::gp_version, "gp_version is nonzero after first use of P::G::G");

##############################
#
{
  # purposely fail.  This one should fail by sensing that "bogus" is bogus, *before* sending 
  # anything to Gnuplot.

  eval{ plot ( {terminal => 'dumb 79 24', output => $testoutput, silent=>1}, with => 'bogus', $x); };
  print "error detection: found\n$@\n";
  ok($@ && $@ =~ /invalid plotstyle \'with\ bogus\' in plot/s,  'we find bogus "with" before sending to gnuplot' )
    or diag "plot() produced no error";

  eval{ plot( {terminal => 'dumb 79 24', output=>$testoutput, topcmds=>"this should fail"}, with=>'line', $x); };
  ok($@ && $@ =~ m/invalid command/o, "we detect an error message from gnuplot");

  PDL::Graphics::Gnuplot::restart();

  unlink($testoutput) or warn "\$!: $!";
}

##############################
# 
my $w;

SKIP:{
    # Check timeout.
    eval {
	 $w = gpwin( 'dumb', size=>[79,24],output=>$testoutput, wait=>1);
    };
    ok((!$@ and (ref $w)), "constructor works");

    skip "Skipping timeout test, which doesn't work under MS Windows", 1
	if($PDL::Graphics::Gnuplot::MS_io_braindamage);

    eval {
	$w->plot ( { topcmds=>'pause 2'}, with=>'line', $x); };

    ok($@ && $@ =~ m/1 second/og, "gnuplot response timeout works" );
}


##############################
{ 
    eval { 
	$w->restart;
    };
    print "restart returned '$@'\n";
    ok(!$@, "restart worked OK\n");

    undef $w;
    ok("destructor worked OK\n");
}


##############################
# Test options parsing

# Some working variables
$x = xvals(51);
my $y = $x*$x; 

do {
 # Object options passed into plot are transient
    $w = gpwin('dumb',size=>[79,24,'ch'], output=>$testoutput);
    $w->options(xr=>[0,30]);
    ok( (defined($w->{options}->{xrange}) and  
	((ref $w->{options}->{xrange}) eq 'ARRAY') and
	($w->{options}->{xrange}->[0] == 0) and
	($w->{options}->{xrange}->[1] == 30))
	, 
	"xr sets xrange option properly in options call" );
    $w->plot($x);

    open FOO, "<$testoutput";
    @lines = <FOO>;
    ok( 0+@lines == 24, "setting 79x24 character dumb output yields 24 lines of output");
    $s = $lines[$#lines - 1];
    $s =~ s/\s*$//; # trim trailing whitespace
    $s =~ s/.*\s//; # trim everything before the final X axis label
    ok( $s == 30, "xrange option generates proper X axis (and dumb terminal behaves as expected)");

    $w->plot($x,{xr=>[0,5]});

    open FOO, "<$testoutput";
    @lines = <FOO>;
    $s = $lines[$#lines - 1];
    $s =~ s/\s*$//; # trim trailing whitespace
    $s =~ s/.*\s//; # trim everything before the final X axis label
    ok( $s == 5, "inline xrange option overrides stored xrange option (and dumb terminal behaves as expected)");

    ok( ((defined($w->{options}->{xrange}) and 
	(ref $w->{options}->{xrange}) eq 'ARRAY' and 
	$w->{options}->{xrange}->[0] == 0 and
	$w->{options}->{xrange}->[1] == 30))
	,
	"inline xrange does not change stored xrange option"
	);

    ok( (defined ($w->{last_plot}) and
	(ref ($w->{last_plot}) eq 'HASH') and
	defined ($w->{last_plot}->{options}) and
	(ref ($w->{last_plot}->{options}) eq 'HASH') and
	defined ($w->{last_plot}->{options}->{xrange}) and
	(ref ($w->{last_plot}->{options}->{xrange}) eq 'ARRAY') and
	$w->{last_plot}->{options}->{xrange}->[0] == 0 and
	$w->{last_plot}->{options}->{xrange}->[1] == 5)
	,
	"inline xrange is stored in last_plot options"
	);
};

unlink($testoutput) or warn "\$!: $!";

##############################
# Test ascii data transfer (binary is tested by default on platforms where it works)
eval {$w = gpwin('dumb', size=>[79,24,'ch'],output=>$testoutput);};
ok((!$@ && !!$w),"opened window for ascii transfer tests");

eval { $w->options( binary=>0 ); }; 
ok( !$@, "set binary mode to 0" );

eval { $w->plot( xvals(5), xvals(5)**2 ); };
ok(!$@, "ascii plot succeeded");

eval { $w->plot( xvals(10000), xvals(10000)->sqrt ); };
ok(!$@, "looong ascii plot succeeded");


##############################
# Test replotting
print "testing replotting...\n";

eval {$w = gpwin('dumb',size=>[79,24,'ch'], output=>$testoutput)};
ok((!$@ && !!$w),"re-opened window");

eval { $w->plot({xr=>[0,30]},xvals(50),xvals(50)**2); };
print $@;
ok(!$@," plot works");


open FOO,"<$testoutput";
@lines = <FOO>;
close FOO;
ok(@lines == 24, "test plot made 24 lines");

eval { $w->restart(); };
ok(!$@,"restart succeeded");

unlink($testoutput) or warn "\$!: $!";
ok(!(-e $testoutput), "test file got deleted");


eval { $w->replot(); };
ok(!$@, "replot works");

open FOO,"<$testoutput";
@l2 = <FOO>;
close FOO;
$w->restart;
unlink($testoutput) or warn "\$!: $!";
ok(@l2 == 24, "test replot made 24 lines");

$same =1;
for $i(0..23) {
    $same &= ($lines[$i] eq $l2[$i]);
}
ok($same, "replot reproduces output");

eval { $w->replot(xvals(50),40*xvals(50)) };
ok(!$@, "replotting and adding a line works");

# lame test - just make sure the plots include at least two lines
# and that one is higher than the other.
open FOO,"<$testoutput";
@l3 = <FOO>;
close FOO;
$w->restart;
unlink($testoutput) or warn "\$!: $!";
ok(@l3==24,"test replot again made 24 lines");

ok($l3[12]=~ m/\#\s+\*/, "test plot has two curves and curve 2 is above curve 1");

# test that options updating modifies the replot
eval { $w->options(yrange=>[200,400]);  $w->replot(); };
ok(!$@, "options set and replot don't crash");

open FOO,"<$testoutput";
@l4 = <FOO>;
close FOO;
$w->restart;
unlink($testoutput) or warn "\$!: $!";
ok(@l4 == 24, "replot made 24 lines after option set");

$same = 1;
for $i(0..23) {
    $same &= ($l3[$i] eq $l4[$i]);
}
ok(!$same, "modifying plot option affects replot");


##############################
# Test parsing of plot options when provided before curve options

$w = gpwin('dumb',size=>[79,24,'ch'], output=>$testoutput);
eval { $w->plot(xmin=>3, xvals(10),xvals(10)); };
ok(!$@, "plot() worked for x,y plot with unescaped plot option");

eval { $w->plot(xrange=>[3,5],xmin=>3,xvals(10),xvals(10)) };
ok($@=~m/No curve option found that matches \'xmin\'/, "xmin after a curve option fails (can't mix curve and plot options)");

eval { $w->plot(xmin=>3,xrange=>[4,5],xvals(10),xvals(10)) };
ok(!$@, "plot works when curve options are given after plot options");

do {
    open FOO,"<$testoutput";
    my @lines = <FOO>;
    ok($lines[22]=~ m/^\s*4\s+.*\s+5\s+$/, "curve option range overrides plot option range");
    close FOO;
};


##############################
# Test parsing of plot options as arrays and/or PDLs, mixed.

eval { $w->plot(xmin=>3,xrange=>[4,5],xvals(10),[1,2,3,4,5,6,7,8,9,10])};
ok(!$@, "two arguments, second one is an array, works OK");

eval { $w->plot(xmin=>3,xrange=>[4,5],[1,2,3,4,5,6,7,8,9,10],xvals(10))};
ok(!$@, "two arguments, second one is an array, works OK");

eval { $w->plot([1,2,3,4,5],[6,7,8,9,10]);};
ok(!$@, "two arguments, both arrays, works OK");

eval { $w->plot(xmin=>3,xrange=>[4,5],xvals(10),[1,2,3])};
ok($@ =~ m/mismatch/, "Mismatch detected in array size vs. PDL size");

##############################
# Test placement of topcmds, extracmds, and bottomcmds
eval { $w->plot(xmin=>3,extracmds=>'reset',xrange=>[4,5],xvals(10),xvals(10)**2); };
ok(!$@, "extracmds does not cause an error");
ok( $PDL::Graphics::Gnuplot::last_plotcmd =~ m/\]\s+reset\s+plot/o, "extracmds inserts exactly one copy in the right place");

eval { $w->plot(xmin=>3,topcmds=>'reset',xrange=>[4,5],xvals(10),xvals(10)**2);};
ok(!$@, "topcmds does not cause an error");
ok( $PDL::Graphics::Gnuplot::last_plotcmd =~ m/set\s+output\s+\"[^\"]+\"\s+reset\s+set\s+palette/o, "topcmds inserts exactly one copy in the right place");

eval { $w->plot(xmin=>3,bottomcmds=>'reset',xrange=>[4,5],xvals(10),xvals(10)**2);};
ok(!$@, "bottomcmds does not cause an error");
ok( $PDL::Graphics::Gnuplot::last_plotcmd =~ m/\]\s+reset\s+set\ssize\snoratio/o, "bottomcmds inserts exactly one copy in the right place");

##############################
# Test tuple size determination: 2-D, 3-D, and variables (palette and variable)
# We do not test the entire lookup table, just that the basic code is working

eval { $w->plot(xvals(10)); } ;
ok(!$@, "2-D line plot accepts one PDL");

eval { $w->plot(xvals(10),xvals(10)); };
ok(!$@, "2-D line plot accepts two PDLs");

eval { $w->plot(xvals(10),xvals(10),xvals(10));};
ok($@ =~ m/Found 3 PDLs for 2D plot type/, "2-D line plot rejects three PDLs");

eval { $w->plot(ps=>'variable',with=>'points',xvals(10),xvals(10),xvals(10)) };
ok(!$@, "2-D plot with one variable parameter takes three PDLs");

eval { $w->plot(ps=>'variable',with=>'points',xvals(10),xvals(10),xvals(10),xvals(10)) };
ok($@ =~ m/Found 4 PDLs for 2D/, "2-D plot with one variable parameter rejects four PDLs");

SKIP: {
    skip "Skipping unsupported mode for deprecated earlier gnuplot",1  
	if($PDL::Graphics::Gnuplot::gp_version < 4.4);
    eval { $w->plot3d(xvals(10,10))};
    ok(!$@, "3-D plot accepts one PDL if it is an image");
};

eval { $w->plot3d(xvals(10),xvals(10)); };
ok($@ =~ m/Found 2 PDLs for 3D/,"3-D plot rejects two PDLs");

eval { $w->plot3d(xvals(10),xvals(10),xvals(10)); };
ok(!$@, "3-D plot accepts three PDLs");

eval { $w->plot3d(xvals(10),xvals(10),xvals(10),xvals(10)); };
ok($@ =~ m/Found 4 PDLs for 3D/,"3-D plot rejects four PDLs");

eval { $w->plot3d(ps=>'variable',with=>'points',xvals(10),xvals(10),xvals(10),xvals(10));};
ok(!$@, "3-D plot accepts four PDLs with one variable element");

eval { $w->plot3d(with=>'points',ps=>'variable',palette=>1,xvals(10),xvals(10),xvals(10),xvals(10));};
ok($@ =~ m/Found 4 PDLs for 3D/,"3-D plot rejects four PDLs with two variable elements");

SKIP: {
    skip "Skipping unsupported mode for deprecated earlier gnuplot",1  
	if($PDL::Graphics::Gnuplot::gp_version < 4.4);
    eval { $w->plot3d(with=>'points',ps=>'variable',palette=>1,xvals(10),xvals(10),xvals(10),xvals(10),xvals(10));};
    ok(!$@, "3-D plot accepts five PDLs with one variable element");
}    ;

eval { $w->plot3d(with=>'points',ps=>'variable',palette=>1,xvals(10),xvals(10),xvals(10),xvals(10),xvals(10),xvals(10));};
ok($@ =~ m/Found 6 PDLs for 3D/,"3-D plot rejects six PDLs with two variable elements");


##############################
# Test threading in arguments
eval { $w->plot(legend=>['line 1'], pdl(2,3,4)); };
ok(!$@, "normal legend plotting works OK");

eval { $w->plot(legend=>['line 1', 'line 2'], pdl(2,3,4)); };
ok($@ =~ m/Legend has 2 entries; but 1 curve/, "Failure to thread crashes");

eval { $w->plot(legend=>['line 1'], pdl([2,3,4],[1,2,3])); };
ok($@ =~ m/Legend has 1 entry; but 2 curve/, "Failure to thread crashes (other way)");

eval { $w->plot(legend=>['line 1','line 2'], pdl([2,3,4],[1,2,3]),[3,4,5]) };
ok($@ =~ m/only 1-D PDLs are allowed to be mixed with array/, "Can't thread with array refs");

eval { $w->plot(legend=>['line 1','line 2'], pdl([2,3,4],[1,2,3]),[3,4]) };
ok($@ =~ m/only 1-D PDLs/, "Mismatched arguments are rejected");

##############################
# Test non-persistence of autoset options
eval { $w->options(xrange=>[1,2]); };
ok((!$@  and  $w->{options}->{xrange}->[0] == 1 and $w->{options}->{xrange}->[1] == 2), "xrange set ok\n");

eval { $w->reset; $w->restart; };
ok(!$@, "reset was ok\n");

ok( !defined($w->{options}->{xrange}), "reset cleared xrange option" );

eval { $w->plot(with=>'lines', xvals(5)); };
ok( !defined($w->{options}->{xrange}), "plotting a line did not set xrange option" );

eval { $w->plot(with=>'image', rvals(5,5)); };
ok( !defined($w->{options}->{xrange}), "plotting an image did not set xrange option" );


##############################
# Test esoteric argument parsing

eval { $w->plot(with=>'lines',y2=>3,xvals(5)); };
ok($@ =~ m/known keyword/ ,"y2 gets rejected");

eval { $w->plot(with=>'lines',xvals(5),{lab2=>['foo',at=>[2,3]]}); };
ok(!$@, "label is accepted ($@)");

##############################
# Test xtics simple-case handling

eval { $w->restart; $w->output('dumb',output=>$testoutput) };
ok(!$@, "gnuplot restart works");

eval { $w->reset; } ;
ok(!$@, "gnuplot reset works");

sub get_axis_testoutput {
    my $file = shift;
    my $n = shift;
    open FOO,"<$file";
    my @lines = <FOO>;
    
    print "\n\n@lines\n\n";
    map { chomp $_ } @lines;
    
    for my $i(0..$#lines) {
	last if( $lines[$#lines] =~ m/[^\s]/ );
	pop @lines;
    }

    return @lines[-1..-$n];
}

eval { $w->plot(xvals(50)->sqrt) };
ok( !$@, "plotting after reset worked ok with autotics" );


$line_nums = (get_axis_testoutput($testoutput, 1));
$line_nums =~ s/^\s+//;
$nums= pdl( split /\s+/,$line_nums);
print "nums is $nums\n";

ok( $nums->nelem==11 && all( $nums == pdl(0,5,10,15,20,25,30,35,40,45,50) ), "autogenerated tics work (case 1)" );


eval { $w->plot(xvals(50)->sqrt,{xtics=>0}) };
ok(!$@, "xvals plot (no xtics) succeeded");
print "($@)\n" if($@);

$line_nums = (get_axis_testoutput($testoutput,1));
ok($line_nums =~ m/\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-/, "No labels with xtics=>0");


eval { $w->plot(xvals(50)->sqrt,{"mxtics"=>{}})};
ok(!$@, "plot with mxtics set to a hash succeeded");

eval { $w->plot(xvals(50)->sqrt,{xtics=>10})};
ok(!$@, "xvals plot(xtics=>10) succeeded");

$line_nums = (get_axis_testoutput($testoutput,1));
$line_nums =~ s/^\s+//;
$nums= pdl( split /\s+/,$line_nums);
ok( $nums->nelem==6 && all( $nums == pdl(0,10,20,30,40,50) ), "tics with spacing 10 work");

eval { $w->plot(xvals(50)->sqrt, {xtics=>[]}) };
ok(!$@, "xvals plot (xtics=>[]) succeeded");

$line_nums = (get_axis_testoutput($testoutput, 1));
$line_nums =~ s/^\s+//;
$nums= pdl( split /\s+/,$line_nums);
ok( $nums->nelem==11 && all( $nums == pdl(0,5,10,15,20,25,30,35,40,45,50) ), "autogenerated tics work (case 2)" );

undef $w;
unlink($testoutput) or warn "\$!: $!";




##############################
# Interactive tests

SKIP: {
    unless(exists($ENV{GNUPLOT_INTERACTIVE})) {
	print STDERR "\n\n******************************\nSkipping 27 interactive tests.\n    Set the environment variable GNUPLOT_INTERACTIVE to enable them.\n******************************\n\n";
	skip "Skipping interactive tests - set env. variable GNUPLOT_INTERACTIVE to enable.",27;
    }

    eval { $w = gpwin('wxt'); };
    if($@) {
	$@ = undef;
	eval { $w = gpwin('x11'); }
    }
    ok(!$@, "created a wxt or x11 plot object");

    ok((ref($PDL::Graphics::Gnuplot::termTab->{$w->{terminal}}) eq 'HASH'), "Terminal is a known type");
    
    ok($PDL::Graphics::Gnuplot::termTab->{$w->{terminal}}->{disp}, "Default terminal is a display type");
    print STDERR "\n\nwindow is type ".$w->{terminal}."\n\n";
    $x = sequence(101)-50;

    eval { $w->plot($x**2); };
    ok(!$@, "plot a parabola to a the display window");
    
    print STDERR "\n\nIs there a display window and does it show a parabola? (Y/n)";
    $a = <STDIN>;
    ok($a !~ m/n/i, "parabola looks OK");

    if($PDL::Graphics::Gnuplot::termTab->{$w->{terminal}}->{disp}>1) {
	print STDERR "\n\nMouse over the plot window.  Are there metrics at bottom that update? (Y/n)";
	$a = <STDIN>;
	ok($a !~ m/n/i, "parabola has metrics");


	if($PDL::Graphics::Gnuplot::gp_version < 4.6) {
	    print STDERR "\n\nYou're running an older gnuplot ($PDL::Graphics::Gnuplot::gp_version) and \nwon't be able to scroll.  You should upgrade.  Skipping scroll test.\n\n";
	    ok(1,"no scroll/zoom test");
	} else {
	    print STDERR "\n\nTry to scroll and zoom the parabola using the scrollbar or (mac) two-fingered\n scrolling in Y; use SHIFT to scroll in X, CTRL to zoom.  Does it work? (Y/n)";
	    $a = <STDIN>;
	    ok($a !~ m/n/i, "parabola can be scrolled and zoomed");
	}
	
	
    } else {
	print STDERR "\n\nThe $w->{terminal} gnuplot terminal has no built-in metrics, skipping that test.\n\n";
	ok(1,"skipping metrics test");

	print STDERR "\n\nThe $w->{terminal} gnuplot terminal has no interactive zoom, skipping that test.\n\n";
	ok(1,"skipping interactive-zoom test");
    }

    eval { $w->reset; $w->options(binary=>0,tee=>1); $w->plot( {title => "Parabola with error bars"},
				with=>"xyerrorbars", legend=>"Parabola",
				$x**2 * 10, abs($x)/10, abs($x)*5 ); };
    print $PDL::Graphics::Gnuplot::last_plotcmd."\n";
        print STDERR "\n\nAre there error bars in both X and Y, both increasing away from the apex, wider in X than Y? (Y/n)";
    $a = <STDIN>;
    ok($a !~ m/n/i, "error bars are OK");

    $xy = zeros(21,21)->ndcoords - pdl(10,10);
    $z = inner($xy, $xy);
    eval {     $w->reset; $w->plot({title  => 'Heat map', 
				    '3d' => 1,
				    view=>[50,30,1],
				    zrange=>[-1,1]
				   },
				   with => 'image', $z*2); 
    };
    ok(!$@, "3-d plot didn't crash");

    print STDERR "\n\nDo you see a purple-yellow colormap image of a radial target, in 3-D? (Y/n)";
    $a = <STDIN>;
    ok($a !~ m/n/i, "3-D heat map plot works OK");
    
    print STDERR "\n\nTry to rotate, pan, and zoom the 3-D image.  Work OK? (Y/n)";
    $a = <STDIN>;
    ok($a !~ m/n/i, "Interact with 3-D image");

    $pi    = 3.14159;
    $theta = zeros(200)->xlinvals(0, 6*$pi);
    $z     = zeros(200)->xlinvals(0, 5);
    eval { $w->reset; $w->plot3d(cos($theta), sin($theta), $z); };

    ok(!$@, "plot3d works");

    print STDERR "\n\nSee a nice 3-D plot of a spiral? (Y/n)";
    $a = <STDIN>;
    ok($a !~ m/n/i, "See a nice 3-D plot of a spiral?");

    $x = xvals(5);
    $y = xvals(5)**2;
    $labels = ['one','two','three','four','five'];
    eval { $w->reset; $w->plot(xr=>[-1,6],yr=>[-1,26],with=>'labels',$x,$y,$labels); };
    print STDERR "\n\nSee the labels with words 'one','two','three','four', and 'five'? (Y/n)";
    $a = <STDIN>;
    ok($a !~ m/n/i, "labels plot is OK");
    
    $x = xvals(51)-25; $y = $x**2;
    eval { $w->reset; $w->plot({title=>"Parabolic fit"},
		 with=>"yerrorbars", legend=>"data", $x, $y+(random($y)-0.5)*2*$y/20, pdl($y/20),
		 with=>"lines",      legend=>"fit",  $x, $y); };
    ok(!$@, "mocked-up fit plot works");
    print STDERR "\n\nSee a green parabola with red error bar points on it? (Y/n)";
    $a = <STDIN>;
    ok($a !~ m/n/i, "parabolic plot is OK");

    $pi    = 3.14159;
    $theta = xvals(201) * 6 * $pi / 200;
    $z     = xvals(201) * 5 / 200;

    eval { $w->reset; $w->plot( {'3d' => 1, title => 'double helix'},
	    with => 'linespoints pointsize variable pointtype 2 palette' ,
	    legend => 'spiral 1',
	    cos($theta), sin($theta), $z, 0.5 + abs(cos($theta)*2),
	    sin($theta/3),
	    with => 'linespoints pointsize variable pointtype 4 palette' ,
	    legend => 'spiral 2',
	    -cos($theta), -sin($theta), $z, 0.5 + abs(cos($theta)*2),
	    sin($theta/3)
	);};	

    ok(!$@, "double helix plot worked");
    
    print STDERR "\n\nSee a double helix plot with variable point sizes and variable color? (Y/n)";
    $a = <STDIN>;
    ok($a !~ m/n/i, "double helix plot is OK");

    eval { $w->reset; $w->plot( with=>'image', rvals(9,9), {xr=>[undef,9]}) };
    ok(!$@, "image plot succeeded");
    print STDERR <<"FOO";


You should see a 9x9 rvals image, scaled from -0.5 to 9.0 in X and -0.5 to 
8.5 in y.  There should be a blank vertical bar 1/2 unit wide at the right 
side of the image.  The other sides of the plot should be flush.  Ok? (Y/n)
FOO
    $a =<STDIN>;

    ok($a !~ m/n/i, "image initial ranging plot is OK");
    
    eval { $w->plot(with=>'image',rvals(9,9), 
		    with=>'image', xvals(9,9)+7, yvals(9,9)+4, rvals(9,9),
		    with=>'line', xvals(20)->sqrt
	       );
    };
    ok(!$@, "two-image range test plot succeeded");
    print STDERR <<"FOO";


You should see two overlapping rvals images, with lower left pixels centered
on (0,0) and (7,4), respectively, and a square root curve superimposed.  
The y range should be flush with the top and bottom of the two images.  The 
x range should be set by the image at left and the curve at right, running 
from -0.5 to 20.0.  The curve should end at 19.0.  Ok? (Y/n)
FOO
    $a = <STDIN>;
    ok($a !~ m/n/i, "image/line ranging plot is OK");

    if($PDL::Bad::Status) {
	eval { 
	    $w = gpwin();
	    $w->multiplot(layout=>[2,1]);
	    $a = xvals(11)**2; 
	    $a->slice("(5)") .= asin(pdl(1.1));
	    $b = (xvals(11)**2)->setbadif(xvals(11)==5);
	    print "a=$a\n";
	    print "b=$b\n";
	    $w->options(xlab=>"X", ylab=>"Y");
	    $w->line($a, {title=>"Parabola with NaN at x=5"});
	    $w->line($b, {title=>"Parabola with BAD at x=5"});
	    $w->end_multi;
	};

	ok(!$@, "bad value plot succeeded");
	print $@ if($@);
	print STDERR <<"FOO";

The two panels should have the same plot with different titles:  Y=X**2, 
with a segment missing from X=4 to X=6.  OK?
FOO
$a = <STDIN>;
	ok($a !~ m/n/i, "bad value plot looks OK");
    } else {
	ok(1, "Skipping bad-value test since this PDL doesn't support badvals");
	ok(1, "Skipping bad-value test since this PDL doesn't support badvals");
    }


##############################
# Mousing tests
#

    if( $ENV{DISPLAY}  and  $PDL::Graphics::Gnuplot::valid_terms->{x11} ) {
	eval { $w=gpwin(x11); $w->image(rvals(9,9), {title=>"X11 window for mouse test"}) };
	ok(!$@, "plotting to x11 window worked.");

	print STDERR "\n\nClick in the X11 window for mouse test.\n";
	eval { my $h = $w->read_mouse(); };
	print STDERR "\n\n$@\n\n" if($@);
	ok(!$@, "Mouse test read a click");

	# Try with a new window
	$w=gpwin($w->{terminal}); 
	eval { print $w->read_mouse(); };
	ok($@ =~ m/no existing/,"Trying to read the mouse input on an empty window doesn't work");
	
    } else {
	ok(1,"Skipping x11 plot");
	ok(1,"Skipping click test for non-x11 device");
	ok(1,"Skipping mouse input test for non-x11 device");
    }
    

}




##############################
# Test date plotting
eval {$w=gpwin( "dumb", size=>[79,24,'ch'],output=>$testoutput );};
ok(!$@, "dumb terminal still works");

# Some date stamps
@dates = (-14552880,   # Apollo 11 launch
	  0,           # UNIX epoch
	  818410080,   # SOHO launch
	  946684799,   # The banking system did not melt down.
	  1054404000); # A happy moment in 2003
$dates = pdl(@dates);

eval { $w->plot( {xdata=>'time'}, with=>'points', $dates->clip(0), xvals($dates) ); };
ok(!$@, "time plotting didn't fail");
print "($@)\n" if($@);
open FOO,"<$testoutput";
$lines1 = join("",(<FOO>));
close FOO;

eval { $w->plot( {xr=>[0,$dates->max],xdata=>'time'}, with=>'points', $dates, xvals($dates) ); };
ok(!$@, "time plotting with range didn't fail");
open FOO,"<$testoutput";
$lines2 = join("",(<FOO>));
close FOO;

eval { $w->plot( {xr=>[$dates->at(3),$dates->at(4)], xdata=>'time'}, with=>'points', $dates, xvals($dates));};
ok(!$@, "time plotting with a different range didn't fail");
open FOO,"<$testoutput";
$lines3 = join("",(<FOO>));
close FOO;

print "lines1:\n$lines1\n\nlines2:\n$lines2\n\nlines3:\n$lines3\n\n";
SKIP: {
    skip "Skipping date ranging tests since Gnuplot itself doesn't work",2;
ok($lines1 eq $lines2,  "Setting the time range to what it would be anyway duplicates the graph");
ok($lines2 cmp $lines3, "Modifying the time range modifies the graph");
}


##############################
# Check that title setting/unsetting works OK
eval { $w->reset; $w->plot({title=>"This is a plot title"},with=>'points',xvals(5));};
ok(!$@, "Title plotting works, no error");

open FOO,"<$testoutput";
@lines = <FOO>;
close FOO;

SKIP:{
    skip "Skipping title tests due to obsolete version of gnuplot (BSD uses 4.2, which fails these)",3 
	if($w->{gp_version} < $PDL::Graphics::Gnuplot::gnuplot_req_v);

    ok($lines[1] =~ m/This is a plot title/, "Plot title gets placed on plot");
    
    
    eval { $w->plot({title=>""},with=>'points',xvals(5));};
    ok(!$@, "Non-title plotting works, no error");
    
    open FOO,"<$testoutput";
    @lines = <FOO>;
    close FOO;
    ok($lines[1] =~ m/^\s*$/, "Setting empty plot title sets an empty title");
}

##############################
# Check that 3D plotting of grids differs from threaded line plotting
SKIP:{
    skip "Skipping 3-D plots since gnuplot is ancient",4
	if($w->{gp_version} < $PDL::Graphics::Gnuplot::gnuplot_req_v);

    eval { $w->plot({trid=>1,title=>""},with=>'lines',sequence(3,3)); };
    ok(!$@, "3-d grid plot with single column succeeded");
    open FOO,"<$testoutput";
    $lines = join("",<FOO>);
    close FOO;
    
    eval { $w->plot({trid=>1,title=>"",yr=>[-1,1]},with=>'lines',cdim=>1,sequence(3,3));};
    ok(!$@, "3-d threaded plot with single column succeeded");
    open FOO,"<$testoutput";
    $lines2 = join("",<FOO>);
    close FOO;
    
    ok( $lines2 ne $lines, "the two 3-D plots differ");
    ok( ($lines2 =~ m/\#/) && ($lines !~ m/\#/) , "the threaded plot has traces the grid lacks");
}

##############################
# Test rudimentary polar plots

eval { $w->plot({trid=>1, mapping=>'cylindrical', angles=>'degrees'},
		wi=>'points',xvals(10)*36,xvals(10)*36,xvals(10)*36); } ;
ok(!$@, "cylindrical plotting in degrees was parsed OK");

eval { $w->plot({trid=>1, mapping=>'sph', angles=>'rad'},
		wi=>'points',xvals(10)*36,xvals(10)*36,xvals(10)*36); } ;
ok(!$@, "spherical plotting in radians was parsed OK (abbrevs in enums too)");

undef $w;
unlink($testoutput) or warn "\$!: $!";

##############################
##############################
## Test aspects of the parsers...
$w = gpwin();

eval { $w->options(xrange=>pdl(1,2)) };
ok(!$@, "xrange accepts a PDL option");

ok( (ref($w->{options}->{xrange}) eq 'ARRAY'   and 
    $w->{options}->{xrange}->[0] == 1         and
    $w->{options}->{xrange}->[1] == 2
     ),
    "xrange parses a 2-PDL into a list ref");

eval { $w->options(xrange=>pdl(1,2,3)) };
ok($@, "xrange rejects a PDL with more than 2 elements");

eval {$w->options(xrange=>[21]);};
ok(!$@, "xrange accepts a single list element");

ok( (  ref($w->{options}->{xrange}) eq 'ARRAY'   and 
       $w->{options}->{xrange}->[0] == 21        and 
       !defined($w->{options}->{xrange}->[1])
    ), "xrange parses single list element correctly");

eval { $w->options(justify=>"0") };
ok(!$@, "justify accepts quoted zero");

eval { $w->options(justify=>"-1") };
ok($@ =~ m/positive/, "justify rejects negative numbers");
undef $@;

eval { $w->options(justify=>"1") };
ok(!$@, "justify accepts positive numbers");

##############################
##############################
## Test explicit and implicit plotting in 2-D and 3-D, both binary and ASCII

$w = gpwin('dumb', output=>$testoutput);

# Test ASCII plot handling
$w->options(binary=>0);

eval { $w->plot(with=>'lines',xvals(5)) };
ok(!$@, "ascii plot with implicit col succeeded");

ok($PDL::Graphics::Gnuplot::last_plotcmd =~ m/plot +\'\-\' +using 0\:1 /,
   "ascii plot with implicit col uses explicit reference to column 0");

eval { $w->plot(with=>'lines',xvals(5),xvals(5)) };
ok(!$@, "ascii plot with no implicit col succeeded");
ok($PDL::Graphics::Gnuplot::last_plotcmd =~ m/plot +\'\-\' +using 1\:2 /s,
   "ascii plot with no implicit cols uses columns 1 and 2");

eval { $w->plot(with=>'lines',xvals(5,5)) };
ok(!$@, "ascii plot with threaded data and implicit column succeeded");
ok($PDL::Graphics::Gnuplot::last_plotcmd =~ m/plot +\'-\' +using 0\:1 [^u]+using 0\:1 /s,
   "threaded ascii plot with one implicit col does the Right Thing");


eval { $w->plot(with=>'lines',xvals(5),{trid=>1}) };
ok(!$@, "ascii 3-d plot with 2 implicit cols succeeded");
ok($PDL::Graphics::Gnuplot::last_plotcmd =~ m/plot +\'-' +using 0\:\(\$0\*0\)\:1 /s,
   "ascii plot with two implicit cols uses column 0 and zeroed-out column 0");

eval { $w->plot(with=>'lines',xvals(5),xvals(5),{trid=>1})};
ok($@, "ascii 3-d plot with 1 implicit col fails (0 or 2 only)");

eval { $w->plot(with=>'lines',xvals(5),xvals(5),xvals(5),{trid=>1}) };
ok(!$@, "ascii 3-d plot with no implicit cols succeeds");
ok($PDL::Graphics::Gnuplot::last_plotcmd=~ m/plot +\'-\' +using 1\:2\:3 /s,
   "ascii 3-d plot with no implicit cols does the Right Thing");

eval { $w->plot(with=>'lines',xvals(5,5),{trid=>1}) };
ok(!$@, "ascii 3-d plot with 2-D data and 2 implicit cols succeeded");
ok($PDL::Graphics::Gnuplot::last_plotcmd =~ m/splot +\"-\" binary array\=\(5,5\) /s,
   "ascii plot with 2-D data and 2 implicit cols uses binary ARRAY mode");

eval { $w->plot(with=>'lines',xvals(5,5),xvals(5,5),{trid=>1}) };
ok($@, "ascii 3-d plot with 2-D data and 1 implicit col fails (0 or 2 only)");

eval { $w->plot(with=>'lines',xvals(5,5),xvals(5,5),xvals(5,5),{trid=>1}) };
ok(!$@, "ascii 3-d plot with 2-D data and no implicit cols succeeded");
ok($PDL::Graphics::Gnuplot::last_plotcmd =~ m/splot +\"-\" binary record\=\(5,5\) /s,
   "ascii plot with 2-D data and no implicit cols uses binary RECORD mode");

eval { $w->plot(with=>'yerrorbars', (xvals(50)-25)**2, pdl(0.5),{binary=>0})  };
ok(!$@, "yerrorbars plot succeeded in ASCII mode");

undef $w;
unlink($testoutput) or warn "\$!: $!";

