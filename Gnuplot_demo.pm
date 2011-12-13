##############################
# Gnuplot_demo package for PDL
#
# To use this manually:
#    use PDL::Demos::Screen;
#    do 'Gnuplot_demo.pm';
#    PDL::Demos::Gnuplot_demo::run();


package PDL::Demos::Gnuplot_demo;

use PDL;
use PDL::Graphics::Gnuplot;

PDL::Demos::Routines->import();
sub comment($);
sub act($);
sub output;

sub run {
    local($PDL::debug) = 0;
    local($PDL::verbose) = 0;
    
    unless( `which gnuplot`) {
	comment q|
This demo illustrates PDL::Graphics::Gnuplot, the PDL interface to the Gnuplot 
plotting language.  It requires the gnuplot executable, which isn't currently
in your path. 

Please install gnuplot (available from http://gnuplot.sourceforge.net) and 
re-run.
|;
	return;
    }

    $s = q|
  # ensure that the module is loaded 
  use PDL::Graphics::Gnuplot;

  # Create a Gnuplot object - the default device displays on most 
  # operating systems.  (No plot window yet - just the object).
  
  $w = gpwin(%%params%%);

  # Create variables to plot
  $x = xvals(1000);
  $y = $x/1000 * sin($x/10);

|;
    if($ENV{DISPLAY}) {
	$subst = "x11, size=>[12,9,'in'], output=>1, title=>'PDL::Graphics::Gnuplot demo window', persist=>0";
    } else {
	$subst = "";
    }
    $s=~s/\%\%params\%\%/$subst/;
    act $s;


   $s = q|
  # ensure that the module is loaded 
  use PDL::Graphics::Gnuplot;

  # Create a Gnuplot object - the default device displays on most 
  # operating systems.  (No plot window yet - just the object).
  $w = gpwin(%%params%%);

  # Create variables to plot
  $x = xvals(1000)/1000;
  $y = $x * sin(100 * $x);

  # Generate a line plot.  Plot parameters in front.
  $w->lines({title=>" x * sin(100 x) ",xl=>"Ordinate",yl=>"Abscissa"}, $x, $y );
|;
    $s =~s/\%\%params\%\%/$subst/;
    act $s;

  act q|
 
  # You can set persistent plot parameters with "options".
  $w->options(title=>"Two lines", xl=>"Ordinate", yl=>"Abscissa");

  # A two-line plot
  $y2 = sqrt($x) * cos(100*$x);
  $w->lines($x,$y,{},$x,$y2);

|;

 act q|
  # You can set persistent plot parameters with "options".
  $w->options(title=>"Two lines", xl=>"Ordinate", yl=>"Abscissa");

  # A two-line plot.  
  # Groups of data are separated by non-PDL options -- in this
  # case, the null hash since there are no per-curve options.

  $y2 = sqrt($x) * cos(100*$x);
  $w->lines($x,$y,{},$x,$y2);

  # A two-line plot with legend.
  # The legend for each line separates the groups of PDL data.

  $w->options(title=>"Two lines (with legend)", key=>'left');
  $w->lines( legend=>"sin",$x,$y,  legend=>"cos",$x,$y2 );

  # 
|;

 act q|
  # You can also generate multiline plots with threading.
  # Here, $x is a 1000-element 1-D PDL, and $yy is a 1000x2 2-D PDL.
  
  $x       = xvals(1000)/1000;
  ($y,$y2) =  ( $x * sin(100 * $x),   sqrt($x) * cos(100 * $x)  );
  $yy      = pdl( $y, $y2 );               

  # all options can be abbreviated to the smallest unique string. 
  # Here, "tit" stands for "title", and "le" for "legend".

  $w->lines({tit=>"2-lines threaded"}, le=>["sin", "cos"], $x, $yy);



|;

act q|
  # line plots are far from the only thing you can do!
  
  # Here is the same plot, with points and some tweaks to the axis labels.
  $w->options(tit=>"2 sets of points");

  $l = ["sin", "cos"];
  $w->points({xtics=>['font "Helvetica Bold,18"'],
              xlab=>"Tilted, Helvetica labels"
             },
             le=>$l, $x, $yy);



|;  

act q|
  # Many types of plot are supported, using the "plot" command
  # and the "with" curve option.  Here, we can mix and match points and lines.

  # You can also set plot options *temporarily* with a hash ref at the start of the
  # plot call:

  $w->plot( {title=>"Points and lines mixed"},
            with=>'points', le=>'sin (points)', $x, $y, 
            with=>'lines',  le=>'cos (line)',   $x, $y2);


|;

act q|
  # Many types of plot are supported, using the "plot" command
  # and the "with" curve option.  Here, we can mix and match points and lines.

  $w->plot( with=>'points', le=>'sin (points)', $x, $y, 
            with=>'lines',  le=>'cos (line)',   $x, $y2);

  $x       = xvals(51)/50;
  ($y,$y2) =  ( $x * sin(20 * $x),   sqrt($x) * cos(20 * $x)  );
  $radii = 0.01 * (0.25 - ($x*2 - 0.5)**2);

  # Here are some other options.  
  $w->plot( {title=>"Circles and Steps"},
            le=>"Circles", with=>'circles', $x, $y, $radii,
            le=>"Steps", with=> 'steps',    $x, $y2
          );
|;

act q|
  # You can plot multiple plots on one pane with "multiplot".

  $x       = xvals(51)/50;
  ($y,$y2) =  ( $x * sin(20 * $x),   sqrt($x) * cos(20 * $x)  );


  $w->multiplot(layout=>[1,2]);

  $w->plot( {title=>"Impulses"}, with=> 'impulses', $x, $y );
  $w->plot( {title=>"Filled Curves"}, with => "filledcurves", $x, $y, $y2 );

  $w->end_multi();
|;

act q|
  # 2-D data...

  $rv = rvals(51,51)/2;
  $im = 25 * cos($rv) / ($rv+1.5);

  $w->multiplot(layout=>[2,2]);
  $w->options(justify=>1);  # set nice aspect ratio
  $w->plot( {tit=>'Default color map'},             with=>'image', $im );
  $w->plot( {tit=>'Grayscale',      clut=>'gray'},  with=>'image', $im );
  $w->plot( {tit=>'heat map',       clut=>'heat1'}, with=>'image', $im );
  $w->plot( {tit=>'3d perspective', trid=>1},       with=>'pm3d',  $im );
  $w->end_multi;

|;



act q|
  # You can indpendently specify color and position on surface plots,
  # and can overlay multiple types of plot -- even in 3D.
  # 
  $rv = rvals(101,101)/5;             $im = cos($rv)/($rv+2.5);
  $grad = sumover $im->range([[-1,0],[1,0]],[$im->dims],'e') * pdl(-1,1);

  $im2 = $im->indexND(ndcoords(26,26)*4);  # subsample $im

  $w->reset;
  $w->options( trid=>1,   hidden=>'front',  colorbox=>0,  clut=>'heat1'  );

  $w->multiplot(layout=>[2,2]);

  $w->plot( {title=>"A colormap-shaded 3-d surface plot"},   with=>'pm3d', $im );

  $w->plot( {title=>"Perspective 3-d surface plot"},         
             with=>'pm3d', xvals($im), yvals($im), $im, $grad );

  $w->plot( {title=>"Perspective grid plot"},
              with=>'lines', xvals($im2)*4, yvals($im2)*4, $im2 );

  $w->plot( {title=>"Combined"},
              with=>'pm3d',  xvals($im),yvals($im), $im, $grad,
              with=>'lines', xvals($im2)*4,  yvals($im2)*4, $im2 );

  $w->end_multi;

|;

 
    use File::Spec;
    $d = File::Spec->catdir( "PDL", "Demos" );
    $m51path = undef;
    foreach my $path ( @INC ) {
	my $check = File::Spec->catdir( $path, $d );
	if ( -d $check ) { $m51path = $check; last; }
    }
    if( defined($m51path) && -e "$m51path/m51.fits") {
	$m51path = "$m51path/m51.fits";
    } else {
	comment q|
  
 ******************************************************
  You seem to be missing the file 'm51.fits', which 
  should be included in the PDL distribution.  Without
  it, I can't show you the m51 image demos, so I'll 
  quit now.  
 ******************************************************
 |;
	return;
    }

    $s =  q|
  # Images ...
 
  $m51 = rfits('%%m51%%');


  $w->reset;
  $w->image({j=>1, clut=>'gray', title=>"M51 galaxy"}, with=>'image',$m51 );
|;

    $s=~ s/\%\%m51\%\%/$m51path/;
    act $s;
  
    $s =  q|

   $m51 = rfits('%%m51%%');

   $m51s = $m51->convolveND(ones(21,21)/21**2);

   $w->options(clut=>'heat2', trid=>1);

   # 3-D display of M51: various angles (note "columnsfirst" in multiplot)

   $w->multiplot(layout=>[2,2,'columnsfirst']);

   $w->plot({title=>"M51 in 3-D (default view)"}, 
             with=>'pm3d',xvals($m51), yvals($m51), $m51s, $m51 );
   $w->plot({title=>"M51 in 3-D (ortho view)",            view=>'equal xy'},
             with=>'pm3d',xvals($m51), yvals($m51), $m51s, $m51 );

   $w->plot({title=>"M51 in 3-D (near-vertical view)",    view=>[ 0, 80, 'equal xy' ]},
             with=>'pm3d',xvals($m51), yvals($m51), $m51s, $m51 );
   $w->plot({title=>"M51 in 3-D (nearly along X axis)",   view=>[ 85, 5 ]},
             with=>'pm3d',xvals($m51), yvals($m51), $m51s, $m51 );
   
   $w->end_multi;

|;
    $s =~ s/\%\%m51\%\%/$m51path/;
    act $s;
}
1;

  

